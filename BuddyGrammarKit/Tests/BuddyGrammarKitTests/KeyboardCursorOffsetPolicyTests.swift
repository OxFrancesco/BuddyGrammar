import BuddyGrammarKit
import XCTest

final class KeyboardCursorOffsetPolicyTests: XCTestCase {
    func testMapsEmojiAndCombiningGraphemesToWholeUTF16Offsets() {
        XCTAssertEqual(
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: -1,
                contextBeforeInput: "go 👍🏽",
                contextAfterInput: nil
            ),
            -4
        )
        XCTAssertEqual(
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: 2,
                contextBeforeInput: nil,
                contextAfterInput: "e\u{301}👨‍👩‍👧‍👦x"
            ),
            13
        )
    }

    func testClampsAtAvailableContextAndSafetyLimit() {
        XCTAssertEqual(
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: -3,
                contextBeforeInput: "ab",
                contextAfterInput: nil
            ),
            -2
        )
        XCTAssertEqual(
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: 100,
                contextBeforeInput: nil,
                contextAfterInput: String(repeating: "a", count: 100),
                maximumGraphemes: 8
            ),
            8
        )
    }

    func testNilContextUsesPlatformFallbackWhileEmptyContextMeansBoundary() {
        XCTAssertEqual(
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: -2,
                contextBeforeInput: nil,
                contextAfterInput: ""
            ),
            -2
        )
        XCTAssertEqual(
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: 2,
                contextBeforeInput: "",
                contextAfterInput: nil
            ),
            2
        )
        XCTAssertEqual(
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: -1,
                contextBeforeInput: "",
                contextAfterInput: nil
            ),
            0
        )
        XCTAssertEqual(
            KeyboardCursorOffsetPolicy.utf16Offset(
                forGraphemeDelta: 1,
                contextBeforeInput: nil,
                contextAfterInput: ""
            ),
            0
        )
    }
}
