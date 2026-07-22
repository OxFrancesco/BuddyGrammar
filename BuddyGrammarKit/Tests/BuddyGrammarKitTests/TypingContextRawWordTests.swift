import BuddyGrammarKit
import XCTest

final class TypingContextRawWordTests: XCTestCase {
    func testRawTrailingWordPreservesApostropheAndNormalizationStyle() {
        XCTAssertEqual(TypingContextAnalyzer.rawTrailingWord(in: "say l'ho"), "l'ho")
        XCTAssertEqual(TypingContextAnalyzer.rawTrailingWord(in: "say l’ho"), "l’ho")

        let decomposed = "cafe\u{301}"
        XCTAssertEqual(
            TypingContextAnalyzer.rawTrailingWord(in: "say \(decomposed)"),
            decomposed
        )
        XCTAssertEqual(
            TypingContextAnalyzer.analyze("say l'ho").mode,
            .typingWord("l’ho")
        )
    }
}
