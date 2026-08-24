/// Grants one opaque pointer or gesture token exclusive ownership of an
/// interaction session until that same token releases it.
///
/// Native keyboard adapters use this small, platform-neutral seam to prevent
/// two simultaneous key gestures from driving the same stateful router.
public struct SinglePointerInteractionOwner<Token: Hashable> {
    public private(set) var activeToken: Token?

    public init() {}

    /// Returns `true` only when `token` acquired an idle session.
    @discardableResult
    public mutating func acquire(_ token: Token) -> Bool {
        guard activeToken == nil else { return false }
        activeToken = token
        return true
    }

    public func owns(_ token: Token) -> Bool {
        activeToken == token
    }

    /// Releases ownership only for the active token. A non-owner is ignored.
    @discardableResult
    public mutating func release(_ token: Token) -> Bool {
        guard activeToken == token else { return false }
        activeToken = nil
        return true
    }

    /// Force-clears ownership for adapter teardown or a layout reset.
    public mutating func reset() {
        activeToken = nil
    }
}
