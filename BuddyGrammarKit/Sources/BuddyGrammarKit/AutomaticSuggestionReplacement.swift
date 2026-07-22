import Foundation

/// Immutable metadata captured when a replacement suggestion is rendered.
///
/// Production adapters validate the exact bounded editor observation before
/// deleting anything. This prevents a stale strip candidate from replacing an
/// unrelated suffix that merely happens to have the same character count.
public struct AutomaticSuggestionReplacement: Equatable, Sendable {
    public let originalText: String
    public let replacementText: String
    public let boundary: String
    public let precedingContext: String
    public let source: AutomaticCorrectionSource

    public init?(
        originalText: String,
        replacementText: String,
        boundary: String,
        precedingContext: String,
        source: AutomaticCorrectionSource
    ) {
        guard !originalText.isEmpty,
              !replacementText.isEmpty,
              originalText != replacementText else {
            return nil
        }
        self.originalText = originalText
        self.replacementText = replacementText
        self.boundary = boundary
        self.precedingContext = precedingContext
        self.source = source
    }

    public var expectedContextBeforeInput: String {
        precedingContext + originalText
    }

    public var insertion: String {
        replacementText + boundary
    }

    public func matches(
        contextBeforeInput: String?,
        deleteCount: Int,
        insertion: String
    ) -> Bool {
        contextBeforeInput == expectedContextBeforeInput
            && deleteCount == originalText.count
            && insertion == self.insertion
    }
}
