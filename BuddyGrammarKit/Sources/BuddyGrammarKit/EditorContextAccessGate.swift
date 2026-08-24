/// The single privacy gate for text that would feed keyboard intelligence.
/// The source closure is deliberately lazy: denied fields do not touch the
/// host editor, which is both a privacy guarantee and an IPC-performance win.
public enum EditorContextAccessGate {
    public static func read<Value>(
        capability: EditorFeatureAccess,
        from source: () -> Value?
    ) -> Value? {
        guard capability.isAllowed else { return nil }
        return source()
    }
}
