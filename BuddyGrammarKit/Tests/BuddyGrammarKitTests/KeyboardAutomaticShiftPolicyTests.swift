import BuddyGrammarKit
import XCTest

final class KeyboardAutomaticShiftPolicyTests: XCTestCase {
    func testUnavailableContextPreservesExistingAutomaticShiftState() {
        XCTAssertNil(
            KeyboardAutomaticShiftPolicy.shouldShift(
                mode: .sentences,
                contextBeforeInput: nil
            )
        )
        XCTAssertNil(
            KeyboardAutomaticShiftPolicy.shouldShift(
                mode: .words,
                contextBeforeInput: nil
            )
        )
    }

    func testKnownEmptyContextIsSentenceAndWordStart() {
        XCTAssertEqual(
            KeyboardAutomaticShiftPolicy.shouldShift(
                mode: .sentences,
                contextBeforeInput: ""
            ),
            true
        )
        XCTAssertEqual(
            KeyboardAutomaticShiftPolicy.shouldShift(
                mode: .words,
                contextBeforeInput: ""
            ),
            true
        )
    }

    func testPunctuationAdditionAndRemovalRecomputeSentenceShift() {
        XCTAssertEqual(
            KeyboardAutomaticShiftPolicy.shouldShift(
                mode: .sentences,
                contextBeforeInput: "Done!"
            ),
            true
        )
        XCTAssertEqual(
            KeyboardAutomaticShiftPolicy.shouldShift(
                mode: .sentences,
                contextBeforeInput: "Done"
            ),
            false
        )
    }

    func testOwnedWordCapitalizationWorksWithoutHostContext() throws {
        var shouldShift = true
        var output = ""

        for character in "john smith" {
            let insertion = shouldShift
                ? String(character).uppercased()
                : String(character)
            output += insertion
            shouldShift = try XCTUnwrap(
                KeyboardAutomaticShiftPolicy.shouldShiftAfterOwnedInsertion(
                    mode: .words,
                    wasShifted: shouldShift,
                    insertedText: insertion
                )
            )
        }

        XCTAssertEqual(output, "John Smith")
    }

    func testOwnedSentenceCapitalizationRearmsWithoutHostContext() throws {
        var shouldShift = true
        var output = ""

        for character in "hello. world\nnext" {
            let insertion = shouldShift
                ? String(character).uppercased()
                : String(character)
            output += insertion
            shouldShift = try XCTUnwrap(
                KeyboardAutomaticShiftPolicy.shouldShiftAfterOwnedInsertion(
                    mode: .sentences,
                    wasShifted: shouldShift,
                    insertedText: insertion
                )
            )
        }

        XCTAssertEqual(output, "Hello. World\nNext")
    }
}
