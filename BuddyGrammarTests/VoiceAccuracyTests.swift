@testable import BuddyGrammar
import XCTest

final class VoiceAccuracyTests: XCTestCase {
    func testVocabularyNormalizesFiltersAndDeduplicatesTerms() {
        let terms = VoiceVocabulary.terms(
            from: "BuddyWrite, OpenRouter\nbuddywrite; mlx swift; invalid <term>"
        )

        XCTAssertEqual(terms, ["BuddyWrite", "OpenRouter", "mlx swift"])
    }

    func testDictationProfileUsesVocabularyAndApplicationContext() {
        let profile = PromptProfile.standard.forDictation(
            vocabulary: ["BuddyWrite", "MLX Swift"],
            applicationName: "Xcode"
        )

        XCTAssertTrue(profile.instruction.contains("raw speech-to-text transcript"))
        XCTAssertTrue(profile.instruction.contains("BuddyWrite"))
        XCTAssertTrue(profile.instruction.contains("MLX Swift"))
        XCTAssertTrue(profile.instruction.contains("Xcode"))
        XCTAssertFalse(profile.instruction.contains(PromptProfile.standardInstruction))
    }

    func testElevenLabsLanguageCodeUsesBaseLanguage() {
        XCTAssertEqual(ElevenLabsSpeechClient.languageCode(for: "en-US"), "en")
        XCTAssertEqual(ElevenLabsSpeechClient.languageCode(for: "it-IT"), "it")
    }
}
