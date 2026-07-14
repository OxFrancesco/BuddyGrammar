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
    public static func analyze(_ context: String?) -> TypingContextAnalysis {
        guard let context, !context.isEmpty else {
            return TypingContextAnalysis(mode: .empty, isAtSentenceStart: true)
        }

        if let last = context.last, isWordCharacter(last) {
            let partial = String(context.reversed().prefix(while: isWordCharacter).reversed())
            let prefix = String(context.dropLast(partial.count))
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
        if let last = trimmed.last, isWordCharacter(last), context.last?.isWhitespace == true {
            lastWord = String(trimmed.reversed().prefix(while: isWordCharacter).reversed())
        }
        return TypingContextAnalysis(
            mode: .betweenWords(lastWord: lastWord),
            isAtSentenceStart: startsSentence(after: context)
        )
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character == "'" || character.isNumber
    }

    private static func startsSentence(after prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        return last == "." || last == "!" || last == "?" || last == "\n" || last == "…"
    }
}
