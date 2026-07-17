import XCTest
import BuddyGrammarKit

final class BuddyGrammarIOSTests: XCTestCase {
    func testStarCorrectionTargetsOnlyTheActiveSentence() throws {
        let candidate = try XCTUnwrap(
            TextContextExtractor.precedingSentence(
                from: "This sentence is already finished.  this sentence need help 🌟  "
            )
        )

        XCTAssertEqual(candidate.requestText, "this sentence need help 🌟")
        XCTAssertEqual(
            candidate.replacement(with: "This sentence needs help 🌟."),
            "  This sentence needs help 🌟.  "
        )
    }

    func testWhitespaceOnlyContextCannotCreateACorrectionRequest() {
        XCTAssertNil(TextCorrectionCandidate(capturedText: " \n\t "))
        XCTAssertNil(TextContextExtractor.precedingSentence(from: "   \n"))
    }

    func testCloudProcessingRequiresExplicitConsentByDefault() {
        let settings = BuddyGrammarSettings.default

        XCTAssertFalse(settings.hasAcceptedCloudProcessing)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertTrue(settings.autoCorrectDictation)
        XCTAssertTrue(settings.automaticallyCorrectWords)
        XCTAssertEqual(settings.correctionUndoDuration, 3)
        XCTAssertTrue(settings.adaptiveTypingEnabled)
        XCTAssertTrue(settings.personalizedPracticeEnabled)
        XCTAssertEqual(
            settings.activeOpenRouterModelID,
            "google/gemini-3.1-flash-lite"
        )
    }
}
