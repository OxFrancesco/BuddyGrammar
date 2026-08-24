import Foundation

public enum KeyboardAutomaticShiftPolicy {
    private static let sentenceBoundaries: Set<Character> = [
        ".", "!", "?", "…", "\n",
    ]

    /// Returns nil when the host withholds context, preserving the keyboard's
    /// existing/manual shift state instead of inventing a document boundary.
    public static func shouldShift(
        mode: EditorAutoCapitalizationMode,
        contextBeforeInput: String?
    ) -> Bool? {
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            guard let contextBeforeInput else { return nil }
            return contextBeforeInput.isEmpty
                || contextBeforeInput.last?.isWhitespace == true
        case .sentences:
            guard let contextBeforeInput else { return nil }
            guard let lastContent = contextBeforeInput.last(where: {
                $0 != " " && $0 != "\t"
            }) else {
                return true
            }
            return sentenceBoundaries.contains(lastContent)
        }
    }

    /// Privacy-safe fallback used only after text this keyboard committed.
    /// Unknown host edits never enter this path, so a context-denied field can
    /// preserve activation/manual state while still advancing its declared
    /// capitalization mode for locally owned input.
    public static func shouldShiftAfterOwnedInsertion(
        mode: EditorAutoCapitalizationMode,
        wasShifted: Bool,
        insertedText: String
    ) -> Bool? {
        guard !insertedText.isEmpty else { return nil }
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            return insertedText.last?.isWhitespace == true
        case .sentences:
            var shouldShift = wasShifted
            for character in insertedText {
                if sentenceBoundaries.contains(character) {
                    shouldShift = true
                } else if !character.isWhitespace {
                    shouldShift = false
                }
            }
            return shouldShift
        }
    }
}
