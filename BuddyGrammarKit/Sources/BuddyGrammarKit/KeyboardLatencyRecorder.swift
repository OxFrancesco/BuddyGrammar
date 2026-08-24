import Dispatch
import Foundation

/// The only latency categories collected by the keyboard. No category carries
/// key labels, committed text, document context, or gesture geometry.
public enum KeyboardLatencyMetric: CaseIterable, Equatable, Hashable, Sendable {
    case keyDownToFeedback
    case keyDownToCommit
    case swipeDecode
}

/// Injectable monotonic time source used by ``KeyboardLatencyRecorder``.
public protocol KeyboardLatencyClock: Sendable {
    func nowNanoseconds() -> UInt64
}

public struct SystemKeyboardLatencyClock: KeyboardLatencyClock {
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

/// An opaque pairing token. It identifies only an in-memory timing event and
/// cannot hold input content.
public struct KeyboardLatencyToken: Equatable, Hashable, Sendable {
    fileprivate let identifier: UInt64
    fileprivate let metric: KeyboardLatencyMetric
}

public struct KeyboardLatencySummary: Equatable, Sendable {
    /// Number of valid samples observed since this in-memory recorder started.
    public let count: UInt64
    /// Number of recent samples represented by the percentile window.
    public let windowCount: Int
    public let p50Milliseconds: Double?
    public let p95Milliseconds: Double?
    public let p99Milliseconds: Double?
}

/// Aggregate-only diagnostics. The snapshot contains no raw durations, event
/// identifiers, ordered events, characters, text, or swipe coordinates.
public struct KeyboardLatencySnapshot: Equatable, Sendable {
    public let keyDownToFeedback: KeyboardLatencySummary
    public let keyDownToCommit: KeyboardLatencySummary
    public let swipeDecode: KeyboardLatencySummary
    public let droppedSampleCount: UInt64
    public let duplicateEventCount: UInt64
    public let lostEventCount: UInt64
    public let inFlightEventCount: Int

    public func summary(for metric: KeyboardLatencyMetric) -> KeyboardLatencySummary {
        switch metric {
        case .keyDownToFeedback: keyDownToFeedback
        case .keyDownToCommit: keyDownToCommit
        case .swipeDecode: swipeDecode
        }
    }
}

/// A content-free, process-memory-only latency recorder for keyboard hot paths.
///
/// Recording performs bounded dictionary/array mutation under a short lock. It
/// never logs, persists, performs network work, or sorts on a hot path. Sorting
/// happens only when an aggregate snapshot is explicitly requested.
public final class KeyboardLatencyRecorder: @unchecked Sendable {
    public static let defaultCapacityPerMetric = 256
    public static let hardMaximumCapacityPerMetric = 512
    public static let defaultMaximumInFlightEvents = 32
    public static let hardMaximumInFlightEvents = 64
    public static let defaultRecentTokenCapacity = 64
    public static let hardMaximumRecentTokenCapacity = 128
    public static let defaultMaximumDurationMilliseconds: Double = 60_000

    /// Shared process-local recorder used by production keyboard seams.
    public static let production = KeyboardLatencyRecorder()

    private struct ActiveEvent {
        let metric: KeyboardLatencyMetric
        let startedAtNanoseconds: UInt64
    }

    /// Reference semantics are intentional: the dictionary never copy-on-writes
    /// a duration array when a sample is appended under the recorder lock.
    private final class SampleWindow {
        var values: [UInt64]
        var nextIndex = 0
        var totalCount: UInt64 = 0

        init(capacity: Int) {
            values = []
            values.reserveCapacity(capacity)
        }

        func append(_ value: UInt64, capacity: Int) -> Bool {
            if totalCount < .max { totalCount += 1 }
            if values.count < capacity {
                values.append(value)
                return false
            }
            values[nextIndex] = value
            nextIndex = (nextIndex + 1) % capacity
            return true
        }

        func summary() -> KeyboardLatencySummary {
            let sorted = values.sorted()
            return KeyboardLatencySummary(
                count: totalCount,
                windowCount: sorted.count,
                p50Milliseconds: percentile(0.50, in: sorted),
                p95Milliseconds: percentile(0.95, in: sorted),
                p99Milliseconds: percentile(0.99, in: sorted)
            )
        }

        private func percentile(_ percentile: Double, in sorted: [UInt64]) -> Double? {
            guard !sorted.isEmpty else { return nil }
            let rank = Int(ceil(percentile * Double(sorted.count)))
            let index = min(sorted.count - 1, max(0, rank - 1))
            return Double(sorted[index]) / 1_000_000
        }
    }

    private let lock = NSLock()
    private let capacityPerMetric: Int
    private let maximumInFlightEvents: Int
    private let recentTokenCapacity: Int
    private let maximumDurationNanoseconds: UInt64
    private let clock: any KeyboardLatencyClock

    private var nextIdentifier: UInt64 = 0
    private var activeEvents: [UInt64: ActiveEvent] = [:]
    private var recentTerminalIdentifiers: [UInt64] = []
    private var recentTerminalNextIndex = 0
    private var recentTerminalIdentifierSet: Set<UInt64> = []
    private let windows: [KeyboardLatencyMetric: SampleWindow]
    private var droppedSampleCount: UInt64 = 0
    private var duplicateEventCount: UInt64 = 0
    private var lostEventCount: UInt64 = 0

    public init(
        capacityPerMetric: Int = defaultCapacityPerMetric,
        maximumInFlightEvents: Int = defaultMaximumInFlightEvents,
        recentTokenCapacity: Int = defaultRecentTokenCapacity,
        maximumDurationMilliseconds: Double = defaultMaximumDurationMilliseconds,
        clock: any KeyboardLatencyClock = SystemKeyboardLatencyClock()
    ) {
        let resolvedCapacityPerMetric = min(
            Self.hardMaximumCapacityPerMetric,
            max(1, capacityPerMetric)
        )
        let resolvedMaximumInFlightEvents = min(
            Self.hardMaximumInFlightEvents,
            max(1, maximumInFlightEvents)
        )
        let resolvedRecentTokenCapacity = min(
            Self.hardMaximumRecentTokenCapacity,
            max(1, recentTokenCapacity)
        )
        self.capacityPerMetric = resolvedCapacityPerMetric
        self.maximumInFlightEvents = resolvedMaximumInFlightEvents
        self.recentTokenCapacity = resolvedRecentTokenCapacity
        let finiteDuration = maximumDurationMilliseconds.isFinite
            ? maximumDurationMilliseconds
            : Self.defaultMaximumDurationMilliseconds
        let clampedDuration = min(
            Self.defaultMaximumDurationMilliseconds,
            max(1, finiteDuration)
        )
        self.maximumDurationNanoseconds = UInt64(clampedDuration * 1_000_000)
        self.clock = clock
        self.windows = Dictionary(
            uniqueKeysWithValues: KeyboardLatencyMetric.allCases.map {
                ($0, SampleWindow(capacity: resolvedCapacityPerMetric))
            }
        )
        self.activeEvents.reserveCapacity(resolvedMaximumInFlightEvents)
        self.recentTerminalIdentifiers.reserveCapacity(resolvedRecentTokenCapacity)
        self.recentTerminalIdentifierSet.reserveCapacity(resolvedRecentTokenCapacity)
    }

    public func begin(_ metric: KeyboardLatencyMetric) -> KeyboardLatencyToken {
        lock.lock()
        defer { lock.unlock() }

        if activeEvents.count >= maximumInFlightEvents,
           let oldestIdentifier = activeEvents.keys.min() {
            activeEvents.removeValue(forKey: oldestIdentifier)
            increment(&droppedSampleCount)
            increment(&lostEventCount)
            rememberTerminal(oldestIdentifier)
        }

        nextIdentifier &+= 1
        if nextIdentifier == 0 { nextIdentifier = 1 }
        let token = KeyboardLatencyToken(identifier: nextIdentifier, metric: metric)
        activeEvents[token.identifier] = ActiveEvent(
            metric: metric,
            startedAtNanoseconds: clock.nowNanoseconds()
        )
        return token
    }

    public func finish(_ token: KeyboardLatencyToken) {
        lock.lock()
        defer { lock.unlock() }

        guard let event = activeEvents.removeValue(forKey: token.identifier) else {
            recordMissingTerminal(token.identifier)
            return
        }
        guard event.metric == token.metric else {
            increment(&lostEventCount)
            increment(&droppedSampleCount)
            rememberTerminal(token.identifier)
            return
        }

        let finishedAt = clock.nowNanoseconds()
        guard finishedAt >= event.startedAtNanoseconds else {
            increment(&droppedSampleCount)
            rememberTerminal(token.identifier)
            return
        }
        let duration = finishedAt - event.startedAtNanoseconds
        guard duration <= maximumDurationNanoseconds else {
            increment(&droppedSampleCount)
            rememberTerminal(token.identifier)
            return
        }

        guard let window = windows[event.metric] else {
            increment(&lostEventCount)
            increment(&droppedSampleCount)
            rememberTerminal(token.identifier)
            return
        }
        if window.append(duration, capacity: capacityPerMetric) {
            increment(&droppedSampleCount)
        }
        rememberTerminal(token.identifier)
    }

    /// Cancels an incomplete measurement. Cancellation discards no content;
    /// it increments the dropped counter so lifecycle gaps remain visible.
    public func cancel(_ token: KeyboardLatencyToken) {
        lock.lock()
        defer { lock.unlock() }

        guard activeEvents.removeValue(forKey: token.identifier) != nil else {
            recordMissingTerminal(token.identifier)
            return
        }
        increment(&droppedSampleCount)
        rememberTerminal(token.identifier)
    }

    @discardableResult
    public func measure<T>(
        _ metric: KeyboardLatencyMetric,
        operation: () throws -> T
    ) rethrows -> T {
        let token = begin(metric)
        defer { finish(token) }
        return try operation()
    }

    public func snapshot() -> KeyboardLatencySnapshot {
        lock.lock()
        defer { lock.unlock() }

        return KeyboardLatencySnapshot(
            keyDownToFeedback: windows[.keyDownToFeedback]!.summary(),
            keyDownToCommit: windows[.keyDownToCommit]!.summary(),
            swipeDecode: windows[.swipeDecode]!.summary(),
            droppedSampleCount: droppedSampleCount,
            duplicateEventCount: duplicateEventCount,
            lostEventCount: lostEventCount,
            inFlightEventCount: activeEvents.count
        )
    }

    private func recordMissingTerminal(_ identifier: UInt64) {
        if recentTerminalIdentifierSet.contains(identifier) {
            increment(&duplicateEventCount)
        } else {
            increment(&lostEventCount)
        }
    }

    private func rememberTerminal(_ identifier: UInt64) {
        guard recentTerminalIdentifierSet.insert(identifier).inserted else { return }
        if recentTerminalIdentifiers.count < recentTokenCapacity {
            recentTerminalIdentifiers.append(identifier)
            return
        }
        let removed = recentTerminalIdentifiers[recentTerminalNextIndex]
        recentTerminalIdentifierSet.remove(removed)
        recentTerminalIdentifiers[recentTerminalNextIndex] = identifier
        recentTerminalNextIndex = (recentTerminalNextIndex + 1) % recentTokenCapacity
    }

    private func increment(_ value: inout UInt64) {
        if value < .max { value += 1 }
    }
}
