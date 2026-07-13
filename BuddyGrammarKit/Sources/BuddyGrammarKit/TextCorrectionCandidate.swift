import Foundation

public struct TextCorrectionCandidate: Equatable, Sendable {
    public let capturedText: String
    public let requestText: String
    public let leadingWhitespace: String
    public let trailingWhitespace: String

    public init?(capturedText: String) {
        let leading = String(capturedText.prefix { $0.isWhitespace })
        let trailing = String(capturedText.reversed().prefix { $0.isWhitespace }.reversed())
        let coreStart = capturedText.index(capturedText.startIndex, offsetBy: leading.count)
        let coreEnd = capturedText.index(capturedText.endIndex, offsetBy: -trailing.count)
        guard coreStart <= coreEnd else { return nil }

        let core = String(capturedText[coreStart..<coreEnd])
        guard !core.isEmpty else { return nil }

        self.capturedText = capturedText
        self.requestText = core
        self.leadingWhitespace = leading
        self.trailingWhitespace = trailing
    }

    public func replacement(with correctedText: String) -> String {
        leadingWhitespace + correctedText + trailingWhitespace
    }
}

public enum TextContextExtractor {
    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "\n"]

    public static func precedingSentence(
        from context: String,
        maximumCharacters: Int = 1_000
    ) -> TextCorrectionCandidate? {
        guard maximumCharacters > 0, !context.isEmpty else { return nil }

        let bounded = String(context.suffix(maximumCharacters))
        let trailingWhitespaceCount = bounded.reversed().prefix { $0.isWhitespace }.count
        let contentEnd = bounded.index(bounded.endIndex, offsetBy: -trailingWhitespaceCount)
        guard contentEnd > bounded.startIndex else { return nil }

        let lastContentIndex = bounded.index(before: contentEnd)
        let searchEnd = sentenceTerminators.contains(bounded[lastContentIndex])
            ? lastContentIndex
            : contentEnd
        let lastTerminator = bounded[..<searchEnd]
            .lastIndex(where: { sentenceTerminators.contains($0) })

        let startIndex: String.Index
        if let lastTerminator {
            startIndex = bounded.index(after: lastTerminator)
        } else {
            startIndex = bounded.startIndex
        }

        return TextCorrectionCandidate(capturedText: String(bounded[startIndex...]))
    }
}
