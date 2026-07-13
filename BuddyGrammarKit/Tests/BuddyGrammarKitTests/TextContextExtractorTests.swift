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
}
