import XCTest
@testable import BuddyGrammarKit

@MainActor
final class CorrectionCompositionSessionTests: XCTestCase {
    func testAutomaticReceiptDefersLearningAndBackspaceRestoresLiteral() {
        let editor = CorrectionCompositionValueEditor(text: "Please type teh")
        var session = CorrectionCompositionSession(
            initialFieldEpoch: 7,
            fieldIdentifier: "message"
        )

        let applied = session.applyAutomatic(
            in: editor,
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "Please type ",
            languageCode: "en-US",
            source: .spelling,
            atMilliseconds: 100
        )

        XCTAssertTrue(applied.didMutateEditor)
        XCTAssertEqual(editor.text, "Please type the ")
        XCTAssertTrue(session.snapshot.hasPendingLearning)

        let reverted = session.backspace(in: editor)

        XCTAssertTrue(reverted.consumedBackspace)
        XCTAssertEqual(editor.text, "Please type teh")
        XCTAssertEqual(reverted.rejection?.source, "spelling")
        XCTAssertFalse(session.snapshot.hasActiveReceipt)
    }

    func testExpiryAcceptsOnlyWhileExactEditorObservationIsStillFresh() {
        let editor = CorrectionCompositionValueEditor(text: "teh")
        var session = CorrectionCompositionSession(fieldIdentifier: "message")
        _ = session.applyAutomatic(
            in: editor,
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "",
            languageCode: "en-US",
            source: .spelling,
            atMilliseconds: 100,
            receiptLifetimeMilliseconds: 3_000
        )

        let early = session.advanceTime(toMilliseconds: 3_099, in: editor)
        XCTAssertNil(early.acceptedLearning)
        XCTAssertTrue(session.snapshot.hasActiveReceipt)

        let expired = session.advanceTime(toMilliseconds: 3_100, in: editor)
        XCTAssertEqual(expired.acceptedLearning?.text, "the")
        XCTAssertFalse(session.snapshot.hasActiveReceipt)
    }

    func testContinuedKeyboardTypingConfirmsLearningBeforeTheEdit() {
        let editor = CorrectionCompositionValueEditor(text: "teh")
        var session = CorrectionCompositionSession(fieldIdentifier: "message")
        _ = session.applyAutomatic(
            in: editor,
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "",
            languageCode: "en-US",
            source: .spelling,
            atMilliseconds: 100
        )

        let confirmation = session.finishActiveReceipt(
            in: editor,
            acceptLearning: true
        )
        editor.replaceTextExternally(editor.text + "n")

        XCTAssertEqual(confirmation.acceptedLearning?.text, "the")
        XCTAssertEqual(editor.text, "the n")
        XCTAssertFalse(session.snapshot.hasActiveReceipt)
    }

    func testFieldChangeInvalidatesReceiptAndStaleAsyncResult() {
        let editor = CorrectionCompositionValueEditor(text: "teh")
        var session = CorrectionCompositionSession(
            initialFieldEpoch: 4,
            fieldIdentifier: "first"
        )
        let stamp = session.captureAsyncStamp()
        session.changeField(to: "second")
        editor.replaceTextExternally("hello")

        let stale = session.applyAsyncAutomatic(
            stamp: stamp,
            in: editor,
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "",
            languageCode: "en-US",
            source: .spelling,
            atMilliseconds: 500
        )

        XCTAssertTrue(stale.ignored)
        XCTAssertEqual(editor.text, "hello")
        XCTAssertEqual(session.snapshot.fieldEpoch, 5)
    }

    func testSuccessfulMutationIsReportedWhenHostContextEchoCannotCreateReceipt() {
        let editor = PostCommitBlindEditor(text: "teh")
        var session = CorrectionCompositionSession(fieldIdentifier: "message")

        let effect = session.applyAutomatic(
            in: editor,
            originalText: "teh",
            replacementText: "the",
            boundary: " ",
            precedingContext: "",
            languageCode: "en-US",
            source: .spelling,
            atMilliseconds: 100
        )

        XCTAssertTrue(effect.didMutateEditor)
        XCTAssertTrue(effect.ignored)
        XCTAssertEqual(editor.text, "the ")
        XCTAssertFalse(session.snapshot.hasActiveReceipt)
    }

    func testExplicitReceiptUsesVisibleWholeOperationUndoButNotBackspace() {
        let editor = CorrectionCompositionValueEditor(text: "i has a cat")
        var session = CorrectionCompositionSession(fieldIdentifier: "message")
        _ = session.applyExplicit(
            in: editor,
            originalText: "i has a cat",
            replacementText: "I have a cat.",
            source: "buddyFix",
            atMilliseconds: 100
        )

        let deletion = session.backspace(in: editor)
        XCTAssertFalse(deletion.consumedBackspace)
        XCTAssertEqual(editor.text, "I have a cat")
        XCTAssertFalse(session.snapshot.hasActiveReceipt)

        editor.replaceTextExternally("i has a cat")
        _ = session.applyExplicit(
            in: editor,
            originalText: "i has a cat",
            replacementText: "I have a cat.",
            source: "buddyFix",
            atMilliseconds: 200
        )
        let undo = session.visibleRevert(in: editor)

        XCTAssertTrue(undo.didMutateEditor)
        XCTAssertEqual(editor.text, "i has a cat")
        XCTAssertEqual(undo.rejection?.source, "buddyFix")
    }
}

@MainActor
private final class PostCommitBlindEditor: CorrectionCompositionEditor {
    private(set) var text: String
    private var hidesContext = false

    init(text: String) {
        self.text = text
    }

    var correctionCompositionText: String {
        hidesContext ? "" : text
    }

    func replaceCorrectionCompositionSuffix(
        _ expectedSuffix: String,
        with replacement: String
    ) -> Bool {
        guard text.hasSuffix(expectedSuffix) else { return false }
        text = String(text.dropLast(expectedSuffix.count)) + replacement
        hidesContext = true
        return true
    }

    func deleteCorrectionCompositionBackward() -> Bool { false }
}
