import XCTest
@testable import BuddyGrammarKit

final class TextContextExtractorTests: XCTestCase {
    func testExtractsTextAfterPreviousSentence() throws {
        let candidate = try XCTUnwrap(
            TextContextExtractor.precedingSentence(from: "Already correct. this are wrong")
        )

        XCTAssertEqual(candidate.capturedText, " this are wrong")
        XCTAssertEqual(candidate.requestText, "this are wrong")
        XCTAssertEqual(candidate.replacement(with: "this is wrong"), " this is wrong")
    }

    func testIncludesFinalPunctuationAndTrailingWhitespace() throws {
        let candidate = try XCTUnwrap(
            TextContextExtractor.precedingSentence(from: "First!  second are wrong.  ")
        )

        XCTAssertEqual(candidate.capturedText, "  second are wrong.  ")
        XCTAssertEqual(candidate.requestText, "second are wrong.")
        XCTAssertEqual(candidate.replacement(with: "Second is wrong."), "  Second is wrong.  ")
    }

    func testTreatsNewlineAsBoundary() throws {
        let candidate = try XCTUnwrap(
            TextContextExtractor.precedingSentence(from: "Heading\nspeling mistake")
        )

        XCTAssertEqual(candidate.requestText, "speling mistake")
    }

    func testPreservesComposedCharacters() throws {
        let candidate = try XCTUnwrap(
            TextContextExtractor.precedingSentence(from: "Done. 👨‍👩‍👧‍👦 cafe\u{301} are nice")
        )

        XCTAssertEqual(candidate.requestText, "👨‍👩‍👧‍👦 cafe\u{301} are nice")
    }

    func testReturnsNilForWhitespaceOnlyContext() {
        XCTAssertNil(TextContextExtractor.precedingSentence(from: "   \n  "))
    }

    func testBoundsLongContext() throws {
        let context = String(repeating: "x", count: 1_500)
        let candidate = try XCTUnwrap(
            TextContextExtractor.precedingSentence(from: context, maximumCharacters: 1_000)
        )

        XCTAssertEqual(candidate.requestText.count, 1_000)
    }

    func testExtractsCurrentSentenceAcrossTheCursor() throws {
        let candidate = try XCTUnwrap(
            TextContextExtractor.currentSentence(
                contextBeforeCursor: "Previous. this sentence ",
                contextAfterCursor: "need fixing. Next"
            )
        )

        XCTAssertEqual(candidate.candidate.capturedText, " this sentence need fixing.")
        XCTAssertEqual(candidate.textBeforeCursor, " this sentence ")
        XCTAssertEqual(candidate.textAfterCursor, "need fixing.")
        XCTAssertEqual(candidate.candidate.requestText, "this sentence need fixing.")
    }

    func testUsesPrecedingSentenceWhenCursorFollowsPunctuation() throws {
        let candidate = try XCTUnwrap(
            TextContextExtractor.currentSentence(
                contextBeforeCursor: "Previous. this need fixing.  ",
                contextAfterCursor: "Next sentence"
            )
        )

        XCTAssertEqual(candidate.candidate.capturedText, " this need fixing.  ")
        XCTAssertEqual(candidate.textAfterCursor, "")
    }

    func testAllAccessibleTextIncludesBothCursorContextsAndSelection() throws {
        let result = try XCTUnwrap(
            TextContextExtractor.allAccessibleText(
                contextBeforeCursor: "First sentence. ",
                selectedText: "this are",
                contextAfterCursor: " the rest."
            )
        )

        XCTAssertEqual(result.candidate.capturedText, "First sentence. this are the rest.")
        XCTAssertEqual(result.candidate.requestText, "First sentence. this are the rest.")
        XCTAssertEqual(result.textBeforeCursor, "First sentence. this are")
        XCTAssertEqual(result.textAfterCursor, " the rest.")
    }

    func testAllAccessibleTextPreservesOuterWhitespace() throws {
        let result = try XCTUnwrap(
            TextContextExtractor.allAccessibleText(
                contextBeforeCursor: "  hello",
                selectedText: nil,
                contextAfterCursor: " world\n"
            )
        )

        XCTAssertEqual(result.candidate.requestText, "hello world")
        XCTAssertEqual(
            result.candidate.replacement(with: "Hello, world."),
            "  Hello, world.\n"
        )
    }

    func testAllAccessibleTextRejectsWhitespaceOnlyInput() {
        XCTAssertNil(
            TextContextExtractor.allAccessibleText(
                contextBeforeCursor: "  ",
                selectedText: "\n",
                contextAfterCursor: "\t"
            )
        )
    }
}
