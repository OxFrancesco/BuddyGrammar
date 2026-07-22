import BuddyGrammarKit
import XCTest

final class KeyboardDeletionPolicyTests: XCTestCase {
    func testDeletesOnlyTheCurrentWordRun() {
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(contextBeforeInput: "hello world"),
            5
        )
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(contextBeforeInput: "can't"),
            5
        )
    }

    func testWhitespaceAndPunctuationAreConservative() {
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(contextBeforeInput: "hello   "),
            3
        )
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(contextBeforeInput: "hello!"),
            1
        )
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(contextBeforeInput: "hello!!!"),
            1
        )
    }

    func testTruncatedRunFallsBackToOneGrapheme() {
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(
                contextBeforeInput: String(repeating: "a", count: 120),
                maximumCount: 32
            ),
            1
        )
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(
                contextBeforeInput: "complete",
                leadingEdgeMayBeTruncated: true
            ),
            1
        )
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(
                contextBeforeInput: String(repeating: "a", count: 80) + " word",
                maximumCount: 32
            ),
            4
        )
        XCTAssertEqual(
            KeyboardDeletionPolicy.deletionCount(contextBeforeInput: ""),
            0
        )
    }
}
