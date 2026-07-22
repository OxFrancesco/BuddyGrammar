@preconcurrency import ActivityKit
import BuddyGrammarKit
import Foundation
import OSLog

private let dynamicIslandLog = Logger(
    subsystem: "com.francescooddo.BuddyGrammar",
    category: "legacy-dictation-readiness"
)

/// Cleans up Live Activities and heartbeat state created by prerelease builds
/// that experimented with keeping the containing app microphone-ready.
///
/// BuddyGrammar no longer starts, restores, or keeps an audio session alive
/// from a custom-keyboard interaction. New dictation sessions begin visibly in
/// the containing app, and Apple-owned Dictation remains the same-field path.
@MainActor
final class DynamicIslandDictationController {
    private let preferences: SharedPreferences?

    init(preferences: SharedPreferences?) {
        self.preferences = preferences
    }

    func deactivate() async {
        preferences?.clearLegacyKeyboardDictationArtifacts()
        for activity in Activity<QuickDictationActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        dynamicIslandLog.notice("Legacy keyboard dictation readiness is disabled")
    }
}
