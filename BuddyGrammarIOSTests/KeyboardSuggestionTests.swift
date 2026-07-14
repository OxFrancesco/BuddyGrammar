import XCTest
import BuddyGrammarKit

final class KeyboardSuggestionTests: XCTestCase {
    func testEmojiMapCoversDocumentedKeywords() {
        XCTAssertEqual(SuggestionEmojiMap.emoji(for: "fire"), "🔥")
        XCTAssertEqual(SuggestionEmojiMap.emoji(for: "Soon"), "🔜")
        XCTAssertNil(SuggestionEmojiMap.emoji(for: "keyboard"))
    }

    func testNextWordPredictionFallsBackToCommonWords() {
        XCTAssertEqual(NextWordPredictor.predictions(after: "see"), ["you", "it"])
        XCTAssertEqual(NextWordPredictor.predictions(after: nil), ["the", "I"])
    }

    func testTypingContextAnalysisDrivesSuggestionKinds() {
        XCTAssertEqual(
            TypingContextAnalyzer.analyze("I love ").mode,
            .betweenWords(lastWord: "love")
        )
        XCTAssertEqual(
            TypingContextAnalyzer.analyze("Hel").mode,
            .typingWord("Hel")
        )
        XCTAssertTrue(TypingContextAnalyzer.analyze("Done! ").isAtSentenceStart)
    }
}
