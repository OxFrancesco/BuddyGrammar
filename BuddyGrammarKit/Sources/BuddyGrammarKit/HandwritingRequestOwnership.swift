public struct HandwritingWorkStamp: Equatable, Sendable {
    public let fieldEpoch: Int
    public let inputRevision: UInt64
    public let requestIdentity: UInt64
}

/// Owns asynchronous handwriting work across field, stroke, and panel changes.
/// A result is publishable only while all three dimensions still match.
public struct HandwritingRequestOwnership: Sendable {
    public private(set) var fieldEpoch: Int
    public private(set) var inputRevision: UInt64 = 0
    private var nextRequestIdentity: UInt64 = 0
    private var active: HandwritingWorkStamp?

    public init(fieldEpoch: Int = 0) {
        self.fieldEpoch = fieldEpoch
    }

    public mutating func changeField(to newFieldEpoch: Int) {
        guard newFieldEpoch != fieldEpoch else { return }
        fieldEpoch = newFieldEpoch
        inputChanged()
    }

    public mutating func inputChanged() {
        inputRevision &+= 1
        active = nil
    }

    public mutating func beginRequest() -> HandwritingWorkStamp {
        nextRequestIdentity &+= 1
        let stamp = HandwritingWorkStamp(
            fieldEpoch: fieldEpoch,
            inputRevision: inputRevision,
            requestIdentity: nextRequestIdentity
        )
        active = stamp
        return stamp
    }

    public func owns(_ stamp: HandwritingWorkStamp) -> Bool {
        active == stamp && isCurrent(stamp)
    }

    public func isCurrent(_ stamp: HandwritingWorkStamp) -> Bool {
        stamp.fieldEpoch == fieldEpoch && stamp.inputRevision == inputRevision
    }

    @discardableResult
    public mutating func finish(_ stamp: HandwritingWorkStamp) -> Bool {
        guard owns(stamp) else { return false }
        active = nil
        return true
    }
}
