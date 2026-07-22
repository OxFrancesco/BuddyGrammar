import Foundation

public enum KeyboardSuggestionTargetOwnership: Equatable, Sendable {
    case contextDerived
    case keyboardOwned
}

/// Immutable editor ownership captured when a suggestion is rendered.
/// Context-derived deletions that touch the leading edge fail closed because
/// `UITextDocumentProxy` does not prove that edge is the document start.
public struct KeyboardSuggestionMutationReceipt: Equatable, Sendable {
    public let fieldEpoch: Int
    public let fieldIdentifier: String
    public let languageCode: String
    public let expectedContextBeforeInput: String
    public let expectedDeletedSuffix: String
    public let deleteCount: Int
    public let targetOwnership: KeyboardSuggestionTargetOwnership

    public init?(
        fieldEpoch: Int,
        fieldIdentifier: String,
        languageCode: String,
        contextBeforeInput: String,
        deleteCount: Int,
        targetOwnership: KeyboardSuggestionTargetOwnership = .contextDerived
    ) {
        guard deleteCount >= 0,
              deleteCount <= contextBeforeInput.count else { return nil }
        if deleteCount > 0,
           targetOwnership == .contextDerived {
            let retainedPrefix = contextBeforeInput.dropLast(deleteCount)
            guard let precedingCharacter = retainedPrefix.last,
                  !WordTokenNormalizer.isWordCharacter(precedingCharacter) else {
                return nil
            }
        }
        self.fieldEpoch = fieldEpoch
        self.fieldIdentifier = fieldIdentifier
        self.languageCode = languageCode
        self.expectedContextBeforeInput = contextBeforeInput
        self.expectedDeletedSuffix = String(contextBeforeInput.suffix(deleteCount))
        self.deleteCount = deleteCount
        self.targetOwnership = targetOwnership
    }

    public func matches(
        fieldEpoch: Int,
        fieldIdentifier: String,
        languageCode: String,
        contextBeforeInput: String
    ) -> Bool {
        self.fieldEpoch == fieldEpoch
            && self.fieldIdentifier == fieldIdentifier
            && self.languageCode == languageCode
            && expectedContextBeforeInput == contextBeforeInput
            && String(contextBeforeInput.suffix(deleteCount)) == expectedDeletedSuffix
    }
}
