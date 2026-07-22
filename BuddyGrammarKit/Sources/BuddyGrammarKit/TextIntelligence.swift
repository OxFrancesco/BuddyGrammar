import Foundation

public enum TextSuggestionKind: Equatable, Sendable {
    case correction
    case completion
    case prediction
}

public struct TextSuggestion: Equatable, Sendable {
    public let text: String
    public let kind: TextSuggestionKind
    public let replacementLength: Int
    public let automaticCorrectionSource: AutomaticCorrectionSource?

    public init(
        text: String,
        kind: TextSuggestionKind,
        replacementLength: Int,
        automaticCorrectionSource: AutomaticCorrectionSource? = nil
    ) {
        self.text = text
        self.kind = kind
        self.replacementLength = replacementLength
        self.automaticCorrectionSource = automaticCorrectionSource
    }
}

/// A single local seam for contextual suggestions and on-device learning.
/// Platform dictionaries can contribute candidates without owning ranking or
/// personalization policy.
public final class TextIntelligence {
    private let personalLanguageModel: PersonalLanguageModel
    private let lexicon: WordFrequencyLexicon

    public init(
        personalLanguageModel: PersonalLanguageModel = PersonalLanguageModel(),
        lexicon: WordFrequencyLexicon = .shared
    ) {
        self.personalLanguageModel = personalLanguageModel
        self.lexicon = lexicon
    }

    public func observeCommittedText(
        _ text: String,
        precededBy context: String?,
        languageCode: String? = nil
    ) {
        personalLanguageModel.learn(
            text: text,
            precededBy: context,
            languageCode: languageCode
        )
    }

    public func usageCount(
        for word: String,
        languageCode: String? = nil
    ) -> Int {
        personalLanguageModel.usageCount(for: word, languageCode: languageCode)
    }

    public func rejectCommittedWord(
        _ word: String,
        precededBy previousWord: String? = nil,
        languageCode: String? = nil
    ) {
        personalLanguageModel.reject(
            previousWord: previousWord,
            word: word,
            languageCode: languageCode
        )
    }

    @discardableResult
    public func addToDictionary(
        _ word: String,
        languageCode: String? = nil
    ) -> Bool {
        let changed = personalLanguageModel.addToDictionary(
            word,
            languageCode: languageCode
        )
        if changed { personalLanguageModel.persist() }
        return changed
    }

    @discardableResult
    public func neverSuggestCorrection(
        typed: String,
        suggestion: String,
        languageCode: String? = nil
    ) -> Bool {
        let changed = personalLanguageModel.suppressCorrection(
            typed: typed,
            suggestion: suggestion,
            languageCode: languageCode
        )
        if changed { personalLanguageModel.persist() }
        return changed
    }

    public func isCorrectionSuppressed(
        typed: String,
        suggestion: String,
        languageCode: String? = nil
    ) -> Bool {
        personalLanguageModel.isCorrectionSuppressed(
            typed: typed,
            suggestion: suggestion,
            languageCode: languageCode
        )
    }

    public func persist() {
        personalLanguageModel.persist()
    }

    public func discardInMemoryPersonalization() {
        personalLanguageModel.discardInMemoryPersonalization()
    }

    public func reloadPersonalization() {
        personalLanguageModel.reloadPersonalization()
    }

    public func suggestions(
        for context: String?,
        shortcutReplacement: String? = nil,
        spellingCandidates: [String] = [],
        completionCandidates: [String] = [],
        languageCode: String? = nil,
        limit: Int = 3
    ) -> [TextSuggestion] {
        guard limit > 0 else { return [] }
        let analysis = TypingContextAnalyzer.analyze(context)
        let usesEnglishPriors = LanguageSupport.usesEnglishPriors(
            languageCode: languageCode
        )

        switch analysis.mode {
        case .typingWord(let partial):
            return wordSuggestions(
                for: partial,
                shortcutReplacement: shortcutReplacement,
                spellingCandidates: spellingCandidates,
                completionCandidates: completionCandidates,
                languageCode: languageCode,
                usesEnglishPriors: usesEnglishPriors,
                limit: limit
            )
        case .betweenWords(let lastWord):
            let words = lastWord == nil
                ? []
                : TextWordTokenizer.trailingSentenceWords(in: context ?? "")
            return predictionSuggestions(
                after: words,
                capitalized: analysis.isAtSentenceStart,
                languageCode: languageCode,
                usesEnglishPriors: usesEnglishPriors,
                limit: limit
            )
        case .empty:
            return predictionSuggestions(
                after: [],
                capitalized: true,
                languageCode: languageCode,
                usesEnglishPriors: usesEnglishPriors,
                limit: limit
            )
        }
    }

    private func wordSuggestions(
        for partial: String,
        shortcutReplacement: String?,
        spellingCandidates: [String],
        completionCandidates: [String],
        languageCode: String?,
        usesEnglishPriors: Bool,
        limit: Int
    ) -> [TextSuggestion] {
        var suggestions: [TextSuggestion] = []
        let normalizedPartial = partial.lowercased()

        if let shortcutReplacement,
           !shortcutReplacement.isEmpty,
           shortcutReplacement.caseInsensitiveCompare(partial) != .orderedSame,
           !personalLanguageModel.isCorrectionSuppressed(
               typed: partial,
               suggestion: shortcutReplacement,
               languageCode: languageCode
           ) {
            append(
                TextSuggestion(
                    text: shortcutReplacement,
                    kind: .correction,
                    replacementLength: partial.count,
                    automaticCorrectionSource: .shortcut
                ),
                to: &suggestions,
                limit: limit
            )
        }

        if partial.count >= 3,
           personalLanguageModel.usageCount(
               for: partial,
               languageCode: languageCode
           ) < 3,
           let correction = LocalWordCorrector.bestCorrection(
               for: partial,
               candidates: spellingCandidates
           ),
           !personalLanguageModel.isCorrectionSuppressed(
               typed: partial,
               suggestion: correction,
               languageCode: languageCode
           ),
           !correction.lowercased().hasPrefix(normalizedPartial) {
            append(
                TextSuggestion(
                    text: correction,
                    kind: .correction,
                    replacementLength: partial.count,
                    automaticCorrectionSource: .spelling
                ),
                to: &suggestions,
                limit: limit
            )
        }

        var completions = personalLanguageModel.completions(
            forPrefix: partial,
            languageCode: languageCode,
            limit: limit
        )
        if lexicon.supports(languageCode: languageCode) {
            completions += lexicon.completions(
                forPrefix: partial,
                languageCode: languageCode,
                limit: limit + 1
            )
        }
        completions += completionCandidates
        completions += spellingCandidates.filter {
            $0.lowercased().hasPrefix(normalizedPartial)
        }

        for completion in completions
        where completion.caseInsensitiveCompare(partial) != .orderedSame {
            let matched = matchingCase(completion, toTyped: partial)
            append(
                TextSuggestion(
                    text: matched,
                    kind: .completion,
                    replacementLength: partial.count
                ),
                to: &suggestions,
                limit: limit
            )
            if suggestions.count == limit { break }
        }
        return suggestions
    }

    private func predictionSuggestions(
        after words: [String],
        capitalized shouldCapitalize: Bool,
        languageCode: String?,
        usesEnglishPriors: Bool,
        limit: Int
    ) -> [TextSuggestion] {
        let predictions = if usesEnglishPriors {
            NextWordPredictor.predictions(
                after: words,
                personal: personalLanguageModel,
                languageCode: languageCode,
                limit: limit
            )
        } else {
            personalLanguageModel.predictions(
                after: words,
                languageCode: languageCode,
                limit: limit
            )
        }
        return predictions.map { word in
            TextSuggestion(
                text: shouldCapitalize ? capitalized(word) : word,
                kind: .prediction,
                replacementLength: 0
            )
        }
    }

    private func append(
        _ suggestion: TextSuggestion,
        to suggestions: inout [TextSuggestion],
        limit: Int
    ) {
        guard suggestions.count < limit,
              !suggestions.contains(where: {
                  $0.text.caseInsensitiveCompare(suggestion.text) == .orderedSame
              }) else {
            return
        }
        suggestions.append(suggestion)
    }

    private func matchingCase(_ word: String, toTyped typed: String) -> String {
        if word == "I" { return word }
        if typed.count > 1,
           typed.contains(where: \.isLetter),
           typed.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return word.uppercased()
        }
        return typed.first?.isUppercase == true ? capitalized(word) : word
    }

    private func capitalized(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }

}

public enum TextWordTokenizer {
    public static func words(in text: String) -> [String] {
        text
            .split(whereSeparator: { !WordTokenNormalizer.isWordCharacter($0) })
            .map { WordTokenNormalizer.canonicalized(String($0)) }
    }

    public static func trailingSentenceWords(in text: String) -> [String] {
        let tail = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: isSentenceTerminator
        ).last.map(String.init) ?? ""
        return words(in: tail)
    }

    static func sentenceSegments(in text: String) -> [[String]] {
        text.split(
            omittingEmptySubsequences: false,
            whereSeparator: isSentenceTerminator
        ).map { words(in: String($0)) }
    }

    private static func isSentenceTerminator(_ character: Character) -> Bool {
        character == "." || character == "!" || character == "?"
            || character == "\n" || character == "…"
    }
}

public enum RecognizedTextFormatter {
    private static let punctuationWithoutLeadingSpace: Set<Character> = [
        ",", ".", ";", ":", "!", "?", "…", ")", "]", "}", "%", "”", "’",
    ]
    private static let openingCharacters: Set<Character> = [
        "(", "[", "{", "/", "#", "@", "\"", "“", "‘",
    ]

    public static func textForInsertion(
        _ text: String,
        contextBeforeInput context: String?
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let previous = context?.last,
              !previous.isWhitespace,
              !openingCharacters.contains(previous),
              let first = trimmed.first,
              !punctuationWithoutLeadingSpace.contains(first) else {
            return trimmed
        }
        return " " + trimmed
    }

    /// Number of trailing spaces or tabs to remove before inserting recognized
    /// text that begins with punctuation which attaches to the preceding word.
    public static func whitespaceToDeleteBefore(
        _ text: String,
        contextBeforeInput context: String?
    ) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              punctuationWithoutLeadingSpace.contains(first) else {
            return 0
        }
        return context?.reversed().prefix { $0 == " " || $0 == "\t" }.count ?? 0
    }
}
