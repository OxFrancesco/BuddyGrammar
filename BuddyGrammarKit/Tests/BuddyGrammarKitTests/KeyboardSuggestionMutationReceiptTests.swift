import BuddyGrammarKit
import XCTest

final class KeyboardSuggestionMutationReceiptTests: XCTestCase {
    func testInsertOnlyReceiptRequiresExactEditorOwnershipAndContext() throws {
        let receipt = try XCTUnwrap(
            KeyboardSuggestionMutationReceipt(
                fieldEpoch: 4,
                fieldIdentifier: "field-a",
                languageCode: "en",
                contextBeforeInput: "Hello ",
                deleteCount: 0
            )
        )

        XCTAssertTrue(
            receipt.matches(
                fieldEpoch: 4,
                fieldIdentifier: "field-a",
                languageCode: "en",
                contextBeforeInput: "Hello "
            )
        )
        XCTAssertFalse(
            receipt.matches(
                fieldEpoch: 4,
                fieldIdentifier: "field-a",
                languageCode: "en",
                contextBeforeInput: "Hello there "
            )
        )
        XCTAssertFalse(
            receipt.matches(
                fieldEpoch: 5,
                fieldIdentifier: "field-a",
                languageCode: "en",
                contextBeforeInput: "Hello "
            )
        )
    }

    func testContextDerivedDeletionRequiresProvenLeadingBoundary() {
        XCTAssertNil(
            KeyboardSuggestionMutationReceipt(
                fieldEpoch: 1,
                fieldIdentifier: "field",
                languageCode: "en",
                contextBeforeInput: "partial",
                deleteCount: 7
            )
        )
        XCTAssertNotNil(
            KeyboardSuggestionMutationReceipt(
                fieldEpoch: 1,
                fieldIdentifier: "field",
                languageCode: "en",
                contextBeforeInput: " partial",
                deleteCount: 7
            )
        )
    }

    func testContextDerivedDeletionRejectsMalformedPartialWordSuffix() {
        XCTAssertNil(
            KeyboardSuggestionMutationReceipt(
                fieldEpoch: 1,
                fieldIdentifier: "field",
                languageCode: "en",
                contextBeforeInput: "thanks   ",
                deleteCount: 5
            )
        )
        XCTAssertNotNil(
            KeyboardSuggestionMutationReceipt(
                fieldEpoch: 1,
                fieldIdentifier: "field",
                languageCode: "en",
                contextBeforeInput: "Before thanks   ",
                deleteCount: 9
            )
        )
    }

    func testKeyboardOwnedTargetMayReachContextLeadingEdge() {
        XCTAssertNotNil(
            KeyboardSuggestionMutationReceipt(
                fieldEpoch: 1,
                fieldIdentifier: "field",
                languageCode: "en",
                contextBeforeInput: "swiped",
                deleteCount: 6,
                targetOwnership: .keyboardOwned
            )
        )
    }
}
