import BuddyGrammarKit
import XCTest

final class AutomaticSuggestionReplacementTests: XCTestCase {
    func testRequiresTheExactCapturedContextAndExplicitBoundary() throws {
        let replacement = try XCTUnwrap(
            AutomaticSuggestionReplacement(
                originalText: "teh",
                replacementText: "the",
                boundary: " ",
                precedingContext: "Please type ",
                source: .spelling
            )
        )

        XCTAssertEqual(replacement.insertion, "the ")
        XCTAssertTrue(
            replacement.matches(
                contextBeforeInput: "Please type teh",
                deleteCount: 3,
                insertion: "the "
            )
        )
        XCTAssertFalse(
            replacement.matches(
                contextBeforeInput: "Unrelated teh",
                deleteCount: 3,
                insertion: "the "
            )
        )
        XCTAssertFalse(
            replacement.matches(
                contextBeforeInput: "Please type teh",
                deleteCount: 3,
                insertion: "the"
            )
        )
    }

    func testRejectsEmptyAndNoOpReplacementMetadata() {
        XCTAssertNil(
            AutomaticSuggestionReplacement(
                originalText: "",
                replacementText: "the",
                boundary: " ",
                precedingContext: "",
                source: .spelling
            )
        )
        XCTAssertNil(
            AutomaticSuggestionReplacement(
                originalText: "the",
                replacementText: "the",
                boundary: "",
                precedingContext: "",
                source: .swipe
            )
        )
    }
}
