import XCTest
@testable import BuddyGrammarKit

final class AutomaticCorrectionReceiptTests: XCTestCase {
    func testImmediateBackspaceRestoresLiteralAndRemovesBoundary() throws {
        let receipt = AutomaticCorrectionReceipt(
            fieldIdentifier: "field-a",
            contextBeforeInput: "Say the ",
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "Say ",
            languageCode: "en-US",
            source: .spelling
        )

        let plan = try XCTUnwrap(
            receipt.revertPlan(
                fieldIdentifier: "field-a",
                contextBeforeInput: "Say the ",
                mode: .immediateBackspace
            )
        )

        XCTAssertEqual(plan.deleteCount, 4)
        XCTAssertEqual(plan.insertion, "teh")
        XCTAssertEqual(plan.rejectedText, "the")
        XCTAssertEqual(plan.acceptedText, "teh")
        XCTAssertEqual(plan.precedingContext, "Say ")
        XCTAssertEqual(plan.languageCode, "en-US")
    }

    func testVisibleUndoRestoresLiteralAndPreservesBoundary() throws {
        let receipt = AutomaticCorrectionReceipt(
            fieldIdentifier: "field-a",
            contextBeforeInput: "Say the ",
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "Say ",
            languageCode: "en-US",
            source: .tapLattice
        )

        let plan = try XCTUnwrap(
            receipt.revertPlan(
                fieldIdentifier: "field-a",
                contextBeforeInput: "Say the ",
                mode: .visibleUndo
            )
        )

        XCTAssertEqual(plan.deleteCount, 4)
        XCTAssertEqual(plan.insertion, "teh ")
        XCTAssertEqual(plan.rejectedText, "the")
    }

    func testRefusesRevertAfterFieldOrDocumentInvalidation() {
        let receipt = AutomaticCorrectionReceipt(
            fieldIdentifier: "field-a",
            contextBeforeInput: "the ",
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "",
            languageCode: "en-US",
            source: .tapLattice
        )

        XCTAssertNil(
            receipt.revertPlan(
                fieldIdentifier: "field-b",
                contextBeforeInput: "the ",
                mode: .immediateBackspace
            )
        )
        XCTAssertNil(
            receipt.revertPlan(
                fieldIdentifier: "field-a",
                contextBeforeInput: "the next",
                mode: .immediateBackspace
            )
        )
    }

    func testRefusesReceiptWhenEditorNeverCommittedReplacement() {
        let receipt = AutomaticCorrectionReceipt(
            fieldIdentifier: "field-a",
            contextBeforeInput: "Say teh ",
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "Say ",
            languageCode: "en-US",
            source: .spelling
        )

        XCTAssertNil(
            receipt.revertPlan(
                fieldIdentifier: "field-a",
                contextBeforeInput: "Say teh ",
                mode: .immediateBackspace
            )
        )
    }
}
