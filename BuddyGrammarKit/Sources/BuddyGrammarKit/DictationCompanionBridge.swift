import Foundation

/// Cross-process signals exchanged between the keyboard extension and the
/// companion (main app) over the Darwin notification center. Darwin
/// notifications carry no payload, so the shared `KeyboardDictationSession`
/// in the App Group remains the source of truth; these signals only wake the
/// other process immediately instead of waiting for its next poll.
public enum DictationCompanionSignal: String, CaseIterable, Sendable {
    case startRequested = "com.francescooddo.BuddyGrammar.dictation.startRequested"
    case stopRequested = "com.francescooddo.BuddyGrammar.dictation.stopRequested"
}

public enum DictationCompanionNotifier {
    /// Posts a signal to every process observing the Darwin notification
    /// center. Safe to call from an app extension.
    public static func post(_ signal: DictationCompanionSignal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(signal.rawValue as CFString),
            nil,
            nil,
            true
        )
    }
}

/// Observes companion dictation signals for the lifetime of the instance.
/// The handler is called on the thread that registered the observer's run
/// loop (typically the main thread).
public final class DictationCompanionObserver {
    private let handler: @Sendable (DictationCompanionSignal) -> Void

    public init(handler: @escaping @Sendable (DictationCompanionSignal) -> Void) {
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for signal in DictationCompanionSignal.allCases {
            CFNotificationCenterAddObserver(
                center,
                observer,
                { _, observer, name, _, _ in
                    guard let observer, let name,
                          let signal = DictationCompanionSignal(
                              rawValue: name.rawValue as String
                          ) else { return }
                    let instance = Unmanaged<DictationCompanionObserver>
                        .fromOpaque(observer)
                        .takeUnretainedValue()
                    instance.handler(signal)
                },
                signal.rawValue as CFString,
                nil,
                .deliverImmediately
            )
        }
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
