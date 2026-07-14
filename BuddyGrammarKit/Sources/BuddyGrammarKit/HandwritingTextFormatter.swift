import Foundation

public enum HandwritingTextFormatter {
    public static func textForInsertion(
        _ recognizedText: String,
        contextBeforeInput: String?,
        languageCode: String? = nil
    ) -> String {
        guard LanguageSupport.usesEnglishPriors(languageCode: languageCode) else {
            return recognizedText
        }
        var text = recognizedText

        let letters = text.filter(\.isLetter)
        let isAllCaps = letters.count > 1
            && letters.contains(where: \.isUppercase)
            && !letters.contains(where: \.isLowercase)
        if isAllCaps {
            text = text.lowercased()
        }

        text = text.replacingOccurrences(
            of: #"\bi\b"#,
            with: "I",
            options: .regularExpression
        )

        guard let firstLetter = text.firstIndex(where: \.isLetter) else {
            return text
        }

        if TypingContextAnalyzer.analyze(contextBeforeInput).isAtSentenceStart {
            text.replaceSubrange(
                firstLetter...firstLetter,
                with: String(text[firstLetter]).uppercased()
            )
        } else if shouldLowercaseFirstWord(of: text, startingAt: firstLetter) {
            text.replaceSubrange(
                firstLetter...firstLetter,
                with: String(text[firstLetter]).lowercased()
            )
        }
        return text
    }

    /// Demotes a leading capital in the middle of a sentence, but only for
    /// plain Title-case words. "I", acronyms ("NASA"), and mixed-case words
    /// ("BuddyGrammar", "iPhone") keep their casing.
    private static func shouldLowercaseFirstWord(
        of text: String,
        startingAt firstLetter: String.Index
    ) -> Bool {
        guard text[firstLetter].isUppercase else { return false }
        let word = String(text[firstLetter...].prefix { $0.isLetter || $0 == "'" })
        guard word != "I", !word.hasPrefix("I'") else { return false }
        return word.dropFirst().allSatisfy { !$0.isUppercase }
    }
}
