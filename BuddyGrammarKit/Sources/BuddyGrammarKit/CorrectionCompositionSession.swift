import Foundation

/// The editor seam used by ``CorrectionCompositionSession``. Production
/// keyboards adapt their native editor here; conformance tests use the bundled
/// value adapter. All replacement methods are compare-and-swap operations so
/// a stale receipt can never overwrite text it did not observe.
@MainActor
public protocol CorrectionCompositionEditor: AnyObject {
    var correctionCompositionText: String { get }

    @discardableResult
    func replaceCorrectionCompositionSuffix(
        _ expectedSuffix: String,
        with replacement: String
    ) -> Bool

    @discardableResult
    func deleteCorrectionCompositionBackward() -> Bool
}

/// A deterministic editor adapter for value-state callers and contract tests.
@MainActor
public final class CorrectionCompositionValueEditor: CorrectionCompositionEditor {
    public private(set) var text: String

    public init(text: String) {
        self.text = text
    }

    public var correctionCompositionText: String { text }

    @discardableResult
    public func replaceCorrectionCompositionSuffix(
        _ expectedSuffix: String,
        with replacement: String
    ) -> Bool {
        guard text.hasSuffix(expectedSuffix) else { return false }
        text = String(text.dropLast(expectedSuffix.count)) + replacement
        return true
    }

    @discardableResult
    public func deleteCorrectionCompositionBackward() -> Bool {
        guard !text.isEmpty else { return false }
        text.removeLast()
        return true
    }

    /// Represents an edit made outside the keyboard session. Call
    /// ``CorrectionCompositionSession/externalEditObserved()`` alongside it.
    public func replaceTextExternally(_ text: String) {
        self.text = text
    }
}

public enum CorrectionCompositionReceiptMode: String, Equatable, Sendable {
    case automatic
    case explicit
}

public struct CorrectionCompositionAsyncStamp: Equatable, Sendable {
    public let fieldEpoch: Int
    public let fieldIdentifier: String

    public init(fieldEpoch: Int, fieldIdentifier: String) {
        self.fieldEpoch = fieldEpoch
        self.fieldIdentifier = fieldIdentifier
    }
}

public struct CorrectionCompositionLearning: Equatable, Sendable {
    public let text: String
    public let originalText: String
    public let precedingContext: String
    public let languageCode: String?
    public let source: String

    public init(
        text: String,
        originalText: String,
        precedingContext: String,
        languageCode: String?,
        source: String
    ) {
        self.text = text
        self.originalText = originalText
        self.precedingContext = precedingContext
        self.languageCode = languageCode
        self.source = source
    }
}

public struct CorrectionCompositionRejection: Equatable, Sendable {
    public let source: String
    public let rejectedText: String
    public let restoredText: String
    public let precedingContext: String
    public let languageCode: String?

    public init(
        source: String,
        rejectedText: String,
        restoredText: String,
        precedingContext: String,
        languageCode: String?
    ) {
        self.source = source
        self.rejectedText = rejectedText
        self.restoredText = restoredText
        self.precedingContext = precedingContext
        self.languageCode = languageCode
    }
}

public struct CorrectionCompositionEffect: Equatable, Sendable {
    public let didMutateEditor: Bool
    public let consumedBackspace: Bool
    public let ignored: Bool
    public let acceptedLearning: CorrectionCompositionLearning?
    public let rejection: CorrectionCompositionRejection?

    public init(
        didMutateEditor: Bool = false,
        consumedBackspace: Bool = false,
        ignored: Bool = false,
        acceptedLearning: CorrectionCompositionLearning? = nil,
        rejection: CorrectionCompositionRejection? = nil
    ) {
        self.didMutateEditor = didMutateEditor
        self.consumedBackspace = consumedBackspace
        self.ignored = ignored
        self.acceptedLearning = acceptedLearning
        self.rejection = rejection
    }
}

public struct CorrectionCompositionSessionSnapshot: Equatable, Sendable {
    public let fieldEpoch: Int
    public let fieldIdentifier: String
    public let receiptID: UUID?
    public let receiptMode: CorrectionCompositionReceiptMode?
    public let receiptSource: String?
    public let originalText: String?
    public let replacementText: String?

    public var hasActiveReceipt: Bool { receiptID != nil }
    public var hasPendingLearning: Bool { hasActiveReceipt }
}

/// Owns the lifecycle of automatic and explicit correction receipts. The
/// interface deliberately combines mutation, staleness, undo, and deferred
/// learning so callers cannot update one lifecycle flag while forgetting the
/// others.
@MainActor
public struct CorrectionCompositionSession {
    private enum NativeReceipt {
        case automatic(AutomaticCorrectionReceipt)
        case explicit
    }

    private struct ActiveReceipt {
        let id: UUID
        let mode: CorrectionCompositionReceiptMode
        let native: NativeReceipt
        let source: String
        let originalText: String
        let replacementText: String
        let boundary: String
        let precedingContext: String
        let languageCode: String?
        let fieldEpoch: Int
        let fieldIdentifier: String
        let expectedEditorText: String
        let expiresAtMilliseconds: Double

        var learning: CorrectionCompositionLearning {
            CorrectionCompositionLearning(
                text: replacementText,
                originalText: originalText,
                precedingContext: precedingContext,
                languageCode: languageCode,
                source: source
            )
        }

        var rejection: CorrectionCompositionRejection {
            CorrectionCompositionRejection(
                source: source,
                rejectedText: replacementText,
                restoredText: originalText,
                precedingContext: precedingContext,
                languageCode: languageCode
            )
        }
    }

    private var fieldEpoch: Int
    private var fieldIdentifier: String
    private var activeReceipt: ActiveReceipt?

    public init(
        initialFieldEpoch: Int = 0,
        fieldIdentifier: String = "unbound"
    ) {
        self.fieldEpoch = initialFieldEpoch
        self.fieldIdentifier = fieldIdentifier
    }

    public var snapshot: CorrectionCompositionSessionSnapshot {
        CorrectionCompositionSessionSnapshot(
            fieldEpoch: fieldEpoch,
            fieldIdentifier: fieldIdentifier,
            receiptID: activeReceipt?.id,
            receiptMode: activeReceipt?.mode,
            receiptSource: activeReceipt?.source,
            originalText: activeReceipt?.originalText,
            replacementText: activeReceipt?.replacementText
        )
    }

    public func captureAsyncStamp() -> CorrectionCompositionAsyncStamp {
        CorrectionCompositionAsyncStamp(
            fieldEpoch: fieldEpoch,
            fieldIdentifier: fieldIdentifier
        )
    }

    public func isFresh(_ stamp: CorrectionCompositionAsyncStamp) -> Bool {
        stamp.fieldEpoch == fieldEpoch && stamp.fieldIdentifier == fieldIdentifier
    }

    /// Use for a definite editor transition. It advances the epoch even when
    /// an editor reuses the same externally supplied identifier.
    public mutating func changeField(to identifier: String) {
        fieldEpoch &+= 1
        fieldIdentifier = identifier
        activeReceipt = nil
    }

    /// Synchronizes identity callbacks that may repeat for the current field.
    public mutating func synchronizeField(identifier: String) {
        guard identifier != fieldIdentifier else { return }
        changeField(to: identifier)
    }

    /// Invalidates pending undo and learning after an unrecognized host edit.
    public mutating func externalEditObserved() {
        activeReceipt = nil
    }

    /// Detects a host edit from the exact observation captured by the receipt.
    @discardableResult
    public mutating func invalidateIfEditorChanged(
        _ editor: any CorrectionCompositionEditor
    ) -> Bool {
        guard let activeReceipt else { return false }
        guard editor.correctionCompositionText != activeReceipt.expectedEditorText else {
            return false
        }
        self.activeReceipt = nil
        return true
    }

    public mutating func applyAutomatic(
        in editor: any CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        boundary: String,
        precedingContext: String,
        languageCode: String?,
        source: AutomaticCorrectionSource,
        atMilliseconds: Double,
        receiptLifetimeMilliseconds: Double = 3_000
    ) -> CorrectionCompositionEffect {
        guard isValidReplacement(originalText, replacementText),
              editor.replaceCorrectionCompositionSuffix(
                  originalText,
                  with: replacementText + boundary
              ) else {
            return CorrectionCompositionEffect(ignored: true)
        }
        let recorded = recordAutomaticApplication(
            in: editor,
            originalText: originalText,
            replacementText: replacementText,
            boundary: boundary,
            precedingContext: precedingContext,
            languageCode: languageCode,
            source: source,
            atMilliseconds: atMilliseconds,
            receiptLifetimeMilliseconds: receiptLifetimeMilliseconds
        )
        return CorrectionCompositionEffect(
            // The compare-and-swap already succeeded. A host that does not
            // immediately echo its new context can prevent receipt creation,
            // but it cannot make the confirmed editor mutation un-happen.
            didMutateEditor: true,
            ignored: recorded.ignored
        )
    }

    public mutating func applyAsyncAutomatic(
        stamp: CorrectionCompositionAsyncStamp,
        in editor: any CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        boundary: String,
        precedingContext: String,
        languageCode: String?,
        source: AutomaticCorrectionSource,
        atMilliseconds: Double,
        receiptLifetimeMilliseconds: Double = 3_000
    ) -> CorrectionCompositionEffect {
        guard isFresh(stamp) else {
            return CorrectionCompositionEffect(ignored: true)
        }
        return applyAutomatic(
            in: editor,
            originalText: originalText,
            replacementText: replacementText,
            boundary: boundary,
            precedingContext: precedingContext,
            languageCode: languageCode,
            source: source,
            atMilliseconds: atMilliseconds,
            receiptLifetimeMilliseconds: receiptLifetimeMilliseconds
        )
    }

    /// Records a replacement already confirmed by a platform editor.
    public mutating func recordAutomaticApplication(
        in editor: any CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        boundary: String,
        precedingContext: String,
        languageCode: String?,
        source: AutomaticCorrectionSource,
        atMilliseconds: Double,
        receiptLifetimeMilliseconds: Double = 3_000
    ) -> CorrectionCompositionEffect {
        let context = editor.correctionCompositionText
        guard isValidReplacement(originalText, replacementText),
              context.hasSuffix(replacementText + boundary) else {
            activeReceipt = nil
            return CorrectionCompositionEffect(ignored: true)
        }
        let native = AutomaticCorrectionReceipt(
            fieldIdentifier: fieldIdentifier,
            contextBeforeInput: context,
            originalText: originalText,
            replacementText: replacementText,
            boundary: boundary,
            precedingContext: precedingContext,
            languageCode: languageCode,
            source: source
        )
        activeReceipt = ActiveReceipt(
            id: native.id,
            mode: .automatic,
            native: .automatic(native),
            source: source.rawValue,
            originalText: originalText,
            replacementText: replacementText,
            boundary: boundary,
            precedingContext: precedingContext,
            languageCode: languageCode,
            fieldEpoch: fieldEpoch,
            fieldIdentifier: fieldIdentifier,
            expectedEditorText: context,
            expiresAtMilliseconds: atMilliseconds + receiptLifetimeMilliseconds
        )
        return CorrectionCompositionEffect()
    }

    public mutating func applyExplicit(
        in editor: any CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        source: String,
        precedingContext: String = "",
        languageCode: String? = nil,
        atMilliseconds: Double,
        receiptLifetimeMilliseconds: Double = 3_000
    ) -> CorrectionCompositionEffect {
        guard isValidReplacement(originalText, replacementText),
              !source.isEmpty,
              editor.replaceCorrectionCompositionSuffix(
                  originalText,
                  with: replacementText
              ) else {
            return CorrectionCompositionEffect(ignored: true)
        }
        let recorded = recordExplicitApplication(
            in: editor,
            originalText: originalText,
            replacementText: replacementText,
            source: source,
            precedingContext: precedingContext,
            languageCode: languageCode,
            atMilliseconds: atMilliseconds,
            receiptLifetimeMilliseconds: receiptLifetimeMilliseconds
        )
        return CorrectionCompositionEffect(
            didMutateEditor: true,
            ignored: recorded.ignored
        )
    }

    /// Records an explicit review proposal already committed by the host.
    public mutating func recordExplicitApplication(
        in editor: any CorrectionCompositionEditor,
        originalText: String,
        replacementText: String,
        source: String,
        precedingContext: String = "",
        languageCode: String? = nil,
        atMilliseconds: Double,
        receiptLifetimeMilliseconds: Double = 3_000
    ) -> CorrectionCompositionEffect {
        let context = editor.correctionCompositionText
        guard isValidReplacement(originalText, replacementText),
              !source.isEmpty,
              context.hasSuffix(replacementText) else {
            activeReceipt = nil
            return CorrectionCompositionEffect(ignored: true)
        }
        activeReceipt = ActiveReceipt(
            id: UUID(),
            mode: .explicit,
            native: .explicit,
            source: source,
            originalText: originalText,
            replacementText: replacementText,
            boundary: "",
            precedingContext: precedingContext,
            languageCode: languageCode,
            fieldEpoch: fieldEpoch,
            fieldIdentifier: fieldIdentifier,
            expectedEditorText: context,
            expiresAtMilliseconds: atMilliseconds + receiptLifetimeMilliseconds
        )
        return CorrectionCompositionEffect()
    }

    public mutating func backspace(
        in editor: any CorrectionCompositionEditor
    ) -> CorrectionCompositionEffect {
        if let receipt = currentReceipt(in: editor),
           receipt.mode == .automatic,
           case .automatic(let native) = receipt.native,
           let plan = native.revertPlan(
               fieldIdentifier: fieldIdentifier,
               contextBeforeInput: editor.correctionCompositionText,
               mode: .immediateBackspace
           ),
           editor.replaceCorrectionCompositionSuffix(
               receipt.replacementText + receipt.boundary,
               with: plan.insertion
           ) {
            activeReceipt = nil
            return CorrectionCompositionEffect(
                didMutateEditor: true,
                consumedBackspace: true,
                rejection: receipt.rejection
            )
        }

        activeReceipt = nil
        return CorrectionCompositionEffect(
            didMutateEditor: editor.deleteCorrectionCompositionBackward()
        )
    }

    public mutating func visibleRevert(
        in editor: any CorrectionCompositionEditor
    ) -> CorrectionCompositionEffect {
        guard let receipt = currentReceipt(in: editor) else {
            activeReceipt = nil
            return CorrectionCompositionEffect(ignored: true)
        }

        let didReplace: Bool
        switch receipt.native {
        case .automatic(let native):
            guard let plan = native.revertPlan(
                fieldIdentifier: fieldIdentifier,
                contextBeforeInput: editor.correctionCompositionText,
                mode: .visibleUndo
            ) else {
                activeReceipt = nil
                return CorrectionCompositionEffect(ignored: true)
            }
            didReplace = editor.replaceCorrectionCompositionSuffix(
                receipt.replacementText + receipt.boundary,
                with: plan.insertion
            )
        case .explicit:
            didReplace = editor.replaceCorrectionCompositionSuffix(
                receipt.replacementText,
                with: receipt.originalText
            )
        }

        activeReceipt = nil
        guard didReplace else {
            return CorrectionCompositionEffect(ignored: true)
        }
        return CorrectionCompositionEffect(
            didMutateEditor: true,
            rejection: receipt.rejection
        )
    }

    public mutating func advanceTime(
        toMilliseconds milliseconds: Double,
        in editor: any CorrectionCompositionEditor
    ) -> CorrectionCompositionEffect {
        guard let receipt = activeReceipt,
              milliseconds >= receipt.expiresAtMilliseconds else {
            return CorrectionCompositionEffect()
        }
        activeReceipt = nil
        guard isReceiptFresh(receipt, in: editor) else {
            return CorrectionCompositionEffect()
        }
        return CorrectionCompositionEffect(acceptedLearning: receipt.learning)
    }

    /// Completes or discards deferred learning before a known keyboard edit.
    public mutating func finishActiveReceipt(
        in editor: any CorrectionCompositionEditor,
        acceptLearning: Bool
    ) -> CorrectionCompositionEffect {
        guard let receipt = activeReceipt else {
            return CorrectionCompositionEffect()
        }
        activeReceipt = nil
        guard acceptLearning, isReceiptFresh(receipt, in: editor) else {
            return CorrectionCompositionEffect()
        }
        return CorrectionCompositionEffect(acceptedLearning: receipt.learning)
    }

    private func isValidReplacement(_ original: String, _ replacement: String) -> Bool {
        !original.isEmpty && !replacement.isEmpty && original != replacement
    }

    private func currentReceipt(
        in editor: any CorrectionCompositionEditor
    ) -> ActiveReceipt? {
        guard let activeReceipt, isReceiptFresh(activeReceipt, in: editor) else {
            return nil
        }
        return activeReceipt
    }

    private func isReceiptFresh(
        _ receipt: ActiveReceipt,
        in editor: any CorrectionCompositionEditor
    ) -> Bool {
        receipt.fieldEpoch == fieldEpoch
            && receipt.fieldIdentifier == fieldIdentifier
            && receipt.expectedEditorText == editor.correctionCompositionText
    }
}
