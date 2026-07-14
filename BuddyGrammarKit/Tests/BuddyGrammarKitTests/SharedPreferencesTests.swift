import XCTest
@testable import BuddyGrammarKit

final class SharedPreferencesTests: XCTestCase {
    func testInstallationIdentifierIsStable() {
        let preferences = SharedPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.installationIdentifier(),
            preferences.installationIdentifier()
        )
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "BuddyGrammarKitTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSettingsRoundTrip() throws {
        let preferences = SharedPreferences(defaults: defaults)
        var settings = BuddyGrammarSettings.default
        settings.openRouterModelID = "test/model"
        settings.usesAutomaticModelUpdates = false
        settings.hasAcceptedCloudProcessing = true
        settings.automaticallyCorrectWords = false
        settings.correctionUndoDuration = 7

        try preferences.saveSettings(settings)

        XCTAssertEqual(preferences.loadSettings(), settings)
    }

    func testLegacySettingsGainLocalAutocorrectionUndoAndImprovedPromptDefaults() throws {
        let legacyInstruction = """
        Fix grammar, spelling, punctuation, and capitalization only.
        Preserve the original language, wording, tone, and meaning as much as possible.
        Do not add explanations, quotes, prefixes, or suffixes.
        Return only the corrected text.
        """
        let data = try JSONSerialization.data(withJSONObject: [
            "openRouterModelID": "test/model",
            "correctionInstruction": legacyInstruction,
            "autoCorrectDictation": true,
            "hasAcceptedCloudProcessing": true,
            "hasCompletedOnboarding": true,
        ])
        defaults.set(data, forKey: "BuddyGrammar.iOS.settings")

        let settings = SharedPreferences(defaults: defaults).loadSettings()

        XCTAssertTrue(settings.automaticallyCorrectWords)
        XCTAssertEqual(settings.correctionUndoDuration, 3)
        XCTAssertEqual(
            settings.correctionInstruction,
            BuddyGrammarConfiguration.standardCorrectionInstruction
        )
        XCTAssertTrue(
            settings.correctionInstruction.localizedCaseInsensitiveContains("adjacent-key")
        )
    }

    func testLegacyManagedModelAutomaticallyMigratesToCurrentDefault() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "openRouterModelID": "openai/gpt-5.4-nano",
            "correctionInstruction": BuddyGrammarConfiguration.standardCorrectionInstruction,
            "autoCorrectDictation": true,
            "hasAcceptedCloudProcessing": true,
            "hasCompletedOnboarding": true,
        ])
        defaults.set(data, forKey: "BuddyGrammar.iOS.settings")

        let settings = SharedPreferences(defaults: defaults).loadSettings()

        XCTAssertTrue(settings.usesAutomaticModelUpdates)
        XCTAssertEqual(
            settings.activeOpenRouterModelID,
            BuddyGrammarConfiguration.defaultOpenRouterModelID
        )
    }

    func testCustomModelDoesNotGetReplacedByAutomaticMigration() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "openRouterModelID": "custom/provider-model",
            "correctionInstruction": BuddyGrammarConfiguration.standardCorrectionInstruction,
            "autoCorrectDictation": true,
            "hasAcceptedCloudProcessing": true,
            "hasCompletedOnboarding": true,
        ])
        defaults.set(data, forKey: "BuddyGrammar.iOS.settings")

        let settings = SharedPreferences(defaults: defaults).loadSettings()

        XCTAssertFalse(settings.usesAutomaticModelUpdates)
        XCTAssertEqual(settings.activeOpenRouterModelID, "custom/provider-model")
    }

    func testKeyboardDictationSessionMovesFromLaunchToAutomaticInsertion() throws {
        let preferences = SharedPreferences(defaults: defaults)
        let sessionID = UUID(uuidString: "7BFA18B2-85C9-48B5-A124-23926CE9144F")!
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let launching = try preferences.beginKeyboardDictationSession(
            id: sessionID,
            now: startedAt
        )
        XCTAssertEqual(launching.phase, .launching)

        let recording = try preferences.updateKeyboardDictationSession(
            id: sessionID,
            phase: .recording,
            now: startedAt.addingTimeInterval(1)
        )
        XCTAssertEqual(recording?.phase, .recording)

        let stopRequested = try preferences.requestKeyboardDictationStop(
            id: sessionID,
            now: startedAt.addingTimeInterval(2)
        )
        XCTAssertEqual(stopRequested?.phase, .stopRequested)

        _ = try preferences.updateKeyboardDictationSession(
            id: sessionID,
            phase: .transcribing,
            now: startedAt.addingTimeInterval(3)
        )
        let ready = try preferences.updateKeyboardDictationSession(
            id: sessionID,
            phase: .ready,
            transcript: "Hello from the keyboard.",
            now: startedAt.addingTimeInterval(4)
        )

        XCTAssertEqual(ready?.phase, .ready)
        XCTAssertEqual(ready?.transcript, "Hello from the keyboard.")
        XCTAssertEqual(
            preferences.loadKeyboardDictationSession(now: startedAt.addingTimeInterval(4)),
            ready
        )
    }

    func testStaleKeyboardDictationSessionIsDiscarded() throws {
        let preferences = SharedPreferences(defaults: defaults)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        _ = try preferences.beginKeyboardDictationSession(now: startedAt)

        XCTAssertNil(
            preferences.loadKeyboardDictationSession(
                now: startedAt.addingTimeInterval(
                    BuddyGrammarConfiguration.keyboardDictationSessionLifetime + 1
                )
            )
        )
    }

    func testPendingTranscriptRoundTripAndClear() throws {
        let preferences = SharedPreferences(defaults: defaults)
        let now = Date(timeIntervalSince1970: 123)
        let transcript = PendingTranscript(
            text: "A dictated sentence.",
            createdAt: now
        )

        try preferences.savePendingTranscript(transcript)
        XCTAssertEqual(preferences.loadPendingTranscript(now: now), transcript)

        preferences.clearPendingTranscript()
        XCTAssertNil(preferences.loadPendingTranscript(now: now))
    }

    func testExpiredPendingTranscriptIsDiscarded() throws {
        let preferences = SharedPreferences(defaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 123)
        let transcript = PendingTranscript(text: "Sensitive draft", createdAt: createdAt)

        try preferences.savePendingTranscript(transcript)

        let afterExpiry = createdAt.addingTimeInterval(
            BuddyGrammarConfiguration.pendingTranscriptLifetime + 1
        )
        XCTAssertNil(preferences.loadPendingTranscript(now: afterExpiry))
        XCTAssertNil(preferences.loadPendingTranscript(now: createdAt))
    }
}
