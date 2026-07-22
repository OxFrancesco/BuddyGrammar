import Foundation

public struct TypingContextAnalysis: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case empty
        case typingWord(String)
        case betweenWords(lastWord: String?)
    }

    public let mode: Mode
    public let isAtSentenceStart: Bool

    public init(mode: Mode, isAtSentenceStart: Bool) {
        self.mode = mode
        self.isAtSentenceStart = isAtSentenceStart
    }
}

public enum TypingContextAnalyzer {
    /// Returns the exact user-entered suffix used for editor mutation and
    /// rollback. Ranking may canonicalize separately, but receipts must never
    /// rewrite apostrophe or normalization style on revert.
    public static func rawTrailingWord(in context: String?) -> String? {
        guard let context,
              context.last.map(WordTokenNormalizer.isWordCharacter) == true else {
            return nil
        }
        return String(
            context.reversed()
                .prefix(while: WordTokenNormalizer.isWordCharacter)
                .reversed()
        )
    }

    /// Returns the exact word-plus-horizontal-whitespace suffix that a
    /// between-words editor mutation must replace. Keeping the raw suffix
    /// together prevents a multi-space or tab run from shifting the deletion
    /// into the middle of the preceding word.
    public static func rawTrailingWordAndHorizontalWhitespace(
        in context: String?
    ) -> String? {
        guard let context else { return nil }
        let trailingWhitespace = String(
            context.reversed()
                .prefix(while: { $0 == " " || $0 == "\t" })
                .reversed()
        )
        guard !trailingWhitespace.isEmpty else { return nil }
        let wordContext = String(context.dropLast(trailingWhitespace.count))
        guard let rawWord = rawTrailingWord(in: wordContext) else { return nil }
        return rawWord + trailingWhitespace
    }

    public static func analyze(_ context: String?) -> TypingContextAnalysis {
        guard let context, !context.isEmpty else {
            return TypingContextAnalysis(mode: .empty, isAtSentenceStart: true)
        }

        if let rawPartial = rawTrailingWord(in: context) {
            let partial = WordTokenNormalizer.canonicalized(rawPartial)
            let prefix = String(context.dropLast(rawPartial.count))
            return TypingContextAnalysis(
                mode: .typingWord(partial),
                isAtSentenceStart: startsSentence(after: prefix)
            )
        }

        let trimmed = String(
            context.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed()
        )
        guard !trimmed.isEmpty else {
            return TypingContextAnalysis(mode: .empty, isAtSentenceStart: true)
        }

        var lastWord: String?
        if let last = trimmed.last,
           WordTokenNormalizer.isWordCharacter(last),
           context.last?.isWhitespace == true {
            lastWord = WordTokenNormalizer.canonicalized(
                String(
                    trimmed.reversed()
                        .prefix(while: WordTokenNormalizer.isWordCharacter)
                        .reversed()
                )
            )
        }
        return TypingContextAnalysis(
            mode: .betweenWords(lastWord: lastWord),
            isAtSentenceStart: startsSentence(after: context)
        )
    }

    private static func startsSentence(after prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        return last == "." || last == "!" || last == "?" || last == "\n" || last == "…"
    }
}
