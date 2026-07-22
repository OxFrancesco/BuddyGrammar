import CoreGraphics

/// Streaming handwriting storage with hard per-stroke and whole-canvas caps.
/// Once full, a rotating reservoir preserves the exact first/latest endpoints
/// and deterministic interior samples without growing on pointer hot paths.
public struct BoundedHandwritingInputBuffer: Sendable {
    private struct SequencedPoint: Sendable {
        let point: CGPoint
        let sequence: UInt64
    }

    private struct BoundedStroke: Sendable {
        let capacity: Int
        var slots: [SequencedPoint] = []
        var replacementOffset = 0

        mutating func append(_ point: SequencedPoint) {
            if slots.count < capacity {
                slots.append(point)
                return
            }
            if capacity == 2 {
                slots[1] = point
                return
            }

            let previousEndpoint = slots[slots.count - 1]
            let replacementIndex = 1 + replacementOffset
            slots[replacementIndex] = previousEndpoint
            slots[slots.count - 1] = point
            replacementOffset = (replacementOffset + 1) % (capacity - 2)
        }

        var snapshot: [CGPoint] {
            slots.sorted { $0.sequence < $1.sequence }.map(\.point)
        }
    }

    public let maximumPointsPerStroke: Int
    public let maximumStrokeCount: Int
    public let maximumTotalPointCount: Int

    private var finished: [[CGPoint]] = []
    private var finishedPointCount = 0
    private var active: BoundedStroke?
    private var nextSequence: UInt64 = 0

    public init(
        maximumPointsPerStroke: Int = 256,
        maximumStrokeCount: Int = 32,
        maximumTotalPointCount: Int = 2_048
    ) {
        precondition(maximumPointsPerStroke >= 2)
        precondition(maximumStrokeCount >= 1)
        precondition(maximumTotalPointCount >= maximumPointsPerStroke)
        self.maximumPointsPerStroke = maximumPointsPerStroke
        self.maximumStrokeCount = maximumStrokeCount
        self.maximumTotalPointCount = maximumTotalPointCount
    }

    public var activeStroke: [CGPoint] { active?.snapshot ?? [] }
    public var finishedStrokes: [[CGPoint]] { finished }
    public var totalPointCount: Int { finishedPointCount + (active?.slots.count ?? 0) }

    public mutating func start(at point: CGPoint) {
        active = nil
        while finished.count >= maximumStrokeCount { removeOldestStroke() }
        makeRoomForAdditionalPoint()
        var stroke = BoundedStroke(capacity: maximumPointsPerStroke)
        stroke.append(sequenced(point))
        active = stroke
    }

    @discardableResult
    public mutating func append(_ point: CGPoint) -> Bool {
        guard var stroke = active else { return false }
        if stroke.slots.count < maximumPointsPerStroke {
            makeRoomForAdditionalPoint()
        }
        stroke.append(sequenced(point))
        active = stroke
        return true
    }

    @discardableResult
    public mutating func endStroke() -> Bool {
        guard let stroke = active else { return false }
        active = nil
        let snapshot = stroke.snapshot
        guard !snapshot.isEmpty else { return false }

        while finished.count >= maximumStrokeCount { removeOldestStroke() }
        while !finished.isEmpty,
              finishedPointCount + snapshot.count > maximumTotalPointCount {
            removeOldestStroke()
        }
        finished.append(snapshot)
        finishedPointCount += snapshot.count
        return true
    }

    public mutating func clear() {
        finished.removeAll(keepingCapacity: true)
        finishedPointCount = 0
        active = nil
        nextSequence = 0
    }

    public static func boundedSnapshot(of strokes: [[CGPoint]]) -> [[CGPoint]] {
        var buffer = BoundedHandwritingInputBuffer()
        for stroke in strokes where !stroke.isEmpty {
            buffer.start(at: stroke[0])
            for point in stroke.dropFirst() { buffer.append(point) }
            buffer.endStroke()
        }
        return buffer.finishedStrokes
    }

    private mutating func makeRoomForAdditionalPoint() {
        while !finished.isEmpty, totalPointCount >= maximumTotalPointCount {
            removeOldestStroke()
        }
    }

    private mutating func removeOldestStroke() {
        let removed = finished.removeFirst()
        finishedPointCount -= removed.count
    }

    private mutating func sequenced(_ point: CGPoint) -> SequencedPoint {
        defer { nextSequence &+= 1 }
        return SequencedPoint(point: point, sequence: nextSequence)
    }
}
