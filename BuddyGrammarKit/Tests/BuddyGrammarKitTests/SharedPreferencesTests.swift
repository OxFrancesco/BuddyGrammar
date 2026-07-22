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

    func testLearningResetGenerationsPersistAndAdvanceIndependently() {
        let preferences = SharedPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.loadLearningResetGenerations(),
            LearningResetGenerations()
        )
        XCTAssertEqual(preferences.advanceLanguageLearningResetGeneration(), 1)
        XCTAssertEqual(
            SharedPreferences(defaults: defaults).loadLearningResetGenerations(),
            LearningResetGenerations(language: 1, typing: 0)
        )
        XCTAssertEqual(preferences.advanceTypingLearningResetGeneration(), 1)
        XCTAssertEqual(
            preferences.loadLearningResetGenerations(),
            LearningResetGenerations(language: 1, typing: 1)
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
        settings.adaptiveTypingEnabled = false
        settings.personalizedPracticeEnabled = false

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
        XCTAssertTrue(settings.adaptiveTypingEnabled)
        XCTAssertTrue(settings.personalizedPracticeEnabled)
        XCTAssertEqual(
            settings.correctionInstruction,
            BuddyGrammarConfiguration.standardCorrectionInstruction
        )
        XCTAssertTrue(
            settings.correctionInstruction.localizedCaseInsensitiveContains("obvious typing errors")
        )
    }

    func testPreviousStandardPromptMigratesToShortLatencyOptimizedPrompt() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "openRouterModelID": "openai/gpt-5.6-luna",
            "usesAutomaticModelUpdates": true,
            "correctionInstruction": BuddyGrammarConfiguration.previousStandardCorrectionInstruction,
            "autoCorrectDictation": true,
            "hasAcceptedCloudProcessing": true,
            "hasCompletedOnboarding": true,
        ])
        defaults.set(data, forKey: "BuddyGrammar.iOS.settings")

        let settings = SharedPreferences(defaults: defaults).loadSettings()

        XCTAssertEqual(
            settings.correctionInstruction,
            BuddyGrammarConfiguration.standardCorrectionInstruction
        )
        XCTAssertEqual(
            settings.activeOpenRouterModelID,
            "google/gemini-3.1-flash-lite"
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

    func testLegacyKeyboardDictationArtifactsAreCleared() {
        let preferences = SharedPreferences(defaults: defaults)
        let sessionKey = "BuddyGrammar.iOS.keyboardDictationSession"
        let heartbeatKey = "BuddyGrammar.iOS.companionHeartbeat"
        defaults.set(Data([0x01]), forKey: sessionKey)
        defaults.set(123.0, forKey: heartbeatKey)

        preferences.clearLegacyKeyboardDictationArtifacts()

        XCTAssertNil(defaults.object(forKey: sessionKey))
        XCTAssertNil(defaults.object(forKey: heartbeatKey))
    }

    func testPendingTranscriptRoundTripAndClear() throws {
        let preferences = SharedPreferences(defaults: defaults)
        let now = Date(timeIntervalSince1970: 123)
        let transcript = PendingTranscript(
            text: "A dictated sentence.",
            languageCode: "en",
            createdAt: now
        )

        try preferences.savePendingTranscript(transcript)
        XCTAssertEqual(preferences.loadPendingTranscript(now: now), transcript)

        preferences.clearPendingTranscript()
        XCTAssertNil(preferences.loadPendingTranscript(now: now))
    }

    func testPendingTranscriptDecodesLegacyPayloadWithoutLanguage() throws {
        struct LegacyPendingTranscript: Encodable {
            let text: String
            let createdAt: Date
        }

        let data = try JSONEncoder().encode(
            LegacyPendingTranscript(
                text: "Legacy transcript",
                createdAt: Date(timeIntervalSince1970: 123)
            )
        )
        let transcript = try JSONDecoder().decode(PendingTranscript.self, from: data)

        XCTAssertEqual(transcript.text, "Legacy transcript")
        XCTAssertNil(transcript.languageCode)
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

    func testSavedDictationPersistsAfterKeyboardHandoffIsCleared() throws {
        let preferences = SharedPreferences(defaults: defaults)
        let dictation = SavedDictation(
            rawTranscript: "hello there",
            text: "Hello there.",
            languageCode: "en",
            createdAt: Date(timeIntervalSince1970: 123)
        )

        try preferences.saveDictation(dictation)
        try preferences.savePendingTranscript(
            PendingTranscript(text: dictation.text, languageCode: dictation.languageCode)
        )
        preferences.clearPendingTranscript()

        XCTAssertNil(preferences.loadPendingTranscript())
        XCTAssertEqual(preferences.loadSavedDictation(), dictation)

        preferences.clearSavedDictation()
        XCTAssertNil(preferences.loadSavedDictation())
    }
}
