import BuddyGrammarKit
import Foundation
import Observation

/// Owns an adaptive practice run without forwarding practice responses to the
/// personal language model. Only `PracticeProfile` aggregates cross processes.
@MainActor
@Observable
final class KeyboardLabModel {
    var selectedTrack: PracticeTrack = .mixed {
        didSet {
            guard selectedTrack != oldValue else { return }
            moveToNextPrompt()
        }
    }

    var response = ""
    private(set) var prompt: PracticePrompt
    private(set) var result: PracticeResult?
    private(set) var profile: PracticeProfile
    private(set) var persistenceMessage: String?

    @ObservationIgnored private var coach: PracticeCoach
    @ObservationIgnored private let store: AdaptiveLearningStore?
    @ObservationIgnored private let personalizesPractice: Bool
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var activeSessionID: UUID?
    @ObservationIgnored private var isPracticeEditorActive = false

    init(
        store: AdaptiveLearningStore? = AdaptiveLearningStore(),
        personalizesPractice: Bool = SharedPreferences()?
            .loadSettings()
            .personalizedPracticeEnabled ?? true,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.personalizesPractice = personalizesPractice
        self.now = now

        let loadedProfile = personalizesPractice
            ? store?.loadPracticeProfile() ?? PracticeProfile()
            : PracticeProfile()
        let loadedCoach = PracticeCoach(profile: loadedProfile)
        profile = loadedProfile
        coach = loadedCoach
        prompt = loadedCoach.nextPrompt(
            request: PracticeRequest(track: .mixed),
            now: now()
        )

        // A prior view or terminated process may have left a short-lived marker.
        // This view publishes a fresh marker only while its editor has focus.
        store?.clearActivePracticeSession()
        if store == nil {
            persistenceMessage = "Practice works here, but shared progress is unavailable."
        }
    }

    var canSubmit: Bool {
        !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && result == nil
    }

    func setPracticeEditorActive(_ isActive: Bool) {
        isPracticeEditorActive = isActive
        if isActive {
            publishActiveSessionIfNeeded()
        } else {
            clearActiveSession()
        }
    }

    func submit() {
        guard canSubmit else { return }

        // Raw and decoded text intentionally use the same visible response for
        // now. The assistance marker keeps evidence calibrated for keyboard help.
        let attempt = PracticeAttempt(
            prompt: prompt,
            rawText: response,
            decodedText: response,
            assistance: .adaptiveKeyboard
        )
        result = coach.record(attempt: attempt, now: now())
        profile = coach.snapshot
        persistProfile()
        clearActiveSession()
    }

    func nextPrompt() {
        moveToNextPrompt()
    }

    func skipPrompt() {
        let attempt = PracticeAttempt(
            prompt: prompt,
            rawText: response,
            decodedText: response,
            assistance: .adaptiveKeyboard,
            abandoned: true
        )
        _ = coach.record(attempt: attempt, now: now())
        profile = coach.snapshot
        persistProfile()
        moveToNextPrompt()
    }

    func resetSession() {
        response = ""
        result = nil
        clearActiveSession()
        publishActiveSessionIfNeeded()
    }

    func endSession() {
        isPracticeEditorActive = false
        clearActiveSession()
    }

    private func moveToNextPrompt() {
        clearActiveSession()
        prompt = coach.nextPrompt(
            request: PracticeRequest(track: selectedTrack),
            now: now()
        )
        response = ""
        result = nil
        publishActiveSessionIfNeeded()
    }

    private func publishActiveSessionIfNeeded() {
        guard isPracticeEditorActive, result == nil, activeSessionID == nil else {
            return
        }
        guard let store else { return }

        let session = ActivePracticeSession(
            promptID: prompt.id,
            expectedText: prompt.expectedText,
            languageCode: "en",
            startedAt: now()
        )
        do {
            try store.saveActivePracticeSession(session)
            activeSessionID = session.id
        } catch {
            persistenceMessage = "The keyboard could not join this practice session."
        }
    }

    private func clearActiveSession() {
        guard let activeSessionID else { return }
        store?.clearActivePracticeSession(id: activeSessionID)
        self.activeSessionID = nil
    }

    private func persistProfile() {
        guard personalizesPractice, let store else { return }
        do {
            try store.savePracticeProfile(profile)
            persistenceMessage = nil
        } catch {
            persistenceMessage = "Practice progress could not be saved."
        }
    }
}
