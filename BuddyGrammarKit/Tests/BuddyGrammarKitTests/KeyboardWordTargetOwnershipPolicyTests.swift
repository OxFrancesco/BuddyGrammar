import BuddyGrammarKit
import XCTest

final class KeyboardWordTargetOwnershipPolicyTests: XCTestCase {
    func testTruncatedLongWordTailFailsClosedWithoutKeyboardOwnership() {
        let proxyTail = String(repeating: "x", count: 64)

        XCTAssertFalse(
            KeyboardWordTargetOwnershipPolicy.isCompleteTarget(
                contextBeforeInput: proxyTail,
                target: proxyTail,
                hasExactKeyboardOwnership: false
            )
        )
    }

    func testVisiblePrecedingBoundaryProvesContextDerivedWord() {
        XCTAssertTrue(
            KeyboardWordTargetOwnershipPolicy.isCompleteTarget(
                contextBeforeInput: "Before safe",
                target: "safe",
                hasExactKeyboardOwnership: false
            )
        )
        XCTAssertFalse(
            KeyboardWordTargetOwnershipPolicy.isCompleteTarget(
                contextBeforeInput: "unsafesafe",
                target: "safe",
                hasExactKeyboardOwnership: false
            )
        )
    }

    func testExactKeyboardOwnershipAllowsTrueDocumentStart() {
        XCTAssertTrue(
            KeyboardWordTargetOwnershipPolicy.isCompleteTarget(
                contextBeforeInput: "typed",
                target: "typed",
                hasExactKeyboardOwnership: true
            )
        )
    }
}
