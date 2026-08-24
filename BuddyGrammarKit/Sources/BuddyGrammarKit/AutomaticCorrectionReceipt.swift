import Foundation

public enum AutomaticCorrectionSource: String, Equatable, Sendable {
    case tapLattice
    case spelling
    case shortcut
    case swipe
}

public enum AutomaticCorrectionRevertMode: Equatable, Sendable {
    /// Mirrors system keyboard behavior: restoring the literal consumes the
    /// boundary whose insertion triggered automatic correction.
    case immediateBackspace

    /// A visible, explicit Undo action restores the word without surprising
    /// the user by deleting an already-visible delimiter.
    case visibleUndo
}

/// Memory-only evidence for one automatic replacement. It intentionally is
/// not Codable so document context cannot accidentally enter persistence.
public struct AutomaticCorrectionReceipt: Equatable, Sendable {
    public let id: UUID
    public let fieldIdentifier: String
    public let contextBeforeInput: String
    public let originalText: String
    public let replacementText: String
    public let boundary: String
    public let precedingContext: String
    public let languageCode: String?
    public let source: AutomaticCorrectionSource

    public init(
        id: UUID = UUID(),
        fieldIdentifier: String,
        contextBeforeInput: String,
        originalText: String,
        replacementText: String,
        boundary: String,
        precedingContext: String,
        languageCode: String?,
        source: AutomaticCorrectionSource
    ) {
        self.id = id
        self.fieldIdentifier = fieldIdentifier
        self.contextBeforeInput = contextBeforeInput
        self.originalText = originalText
        self.replacementText = replacementText
        self.boundary = boundary
        self.precedingContext = precedingContext
        self.languageCode = languageCode
        self.source = source
    }

    public func revertPlan(
        fieldIdentifier currentFieldIdentifier: String,
        contextBeforeInput currentContextBeforeInput: String,
        mode: AutomaticCorrectionRevertMode
    ) -> AutomaticCorrectionRevertPlan? {
        guard currentFieldIdentifier == fieldIdentifier,
              currentContextBeforeInput == contextBeforeInput,
              contextBeforeInput.hasSuffix(replacementText + boundary) else {
            return nil
        }
        let restoredBoundary = mode == .visibleUndo ? boundary : ""
        return AutomaticCorrectionRevertPlan(
            deleteCount: replacementText.count + boundary.count,
            insertion: originalText + restoredBoundary,
            rejectedText: replacementText,
            acceptedText: originalText,
            precedingContext: precedingContext,
            languageCode: languageCode
        )
    }
}

public struct AutomaticCorrectionRevertPlan: Equatable, Sendable {
    public let deleteCount: Int
    public let insertion: String
    public let rejectedText: String
    public let acceptedText: String
    public let precedingContext: String
    public let languageCode: String?

    public init(
        deleteCount: Int,
        insertion: String,
        rejectedText: String,
        acceptedText: String,
        precedingContext: String,
        languageCode: String?
    ) {
        self.deleteCount = deleteCount
        self.insertion = insertion
        self.rejectedText = rejectedText
        self.acceptedText = acceptedText
        self.precedingContext = precedingContext
        self.languageCode = languageCode
    }
}
