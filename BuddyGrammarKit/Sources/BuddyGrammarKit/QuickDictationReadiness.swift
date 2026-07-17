import Foundation

#if os(iOS)
import ActivityKit
#endif

public enum QuickDictationDuration: String, Codable, CaseIterable, Equatable, Sendable {
    case fiveMinutes
    case twelveHours
    case always

    public var interval: TimeInterval? {
        switch self {
        case .fiveMinutes:
            5 * 60
        case .twelveHours:
            12 * 60 * 60
        case .always:
            nil
        }
    }

    public func expirationDate(startedAt: Date) -> Date? {
        interval.map { startedAt.addingTimeInterval($0) }
    }
}

#if os(iOS)
public struct QuickDictationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case ready
            case recording
            case processing
        }

        public var phase: Phase
        public var startedAt: Date?

        public init(phase: Phase, startedAt: Date? = nil) {
            self.phase = phase
            self.startedAt = startedAt
        }
    }

    public let activatedAt: Date

    public init(activatedAt: Date) {
        self.activatedAt = activatedAt
    }
}
#endif
