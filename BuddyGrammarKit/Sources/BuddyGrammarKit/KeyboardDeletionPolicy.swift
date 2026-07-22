import Foundation

public enum KeyboardDeletionPolicy {
    /// Returns a conservative grapheme count for one accelerated delete step.
    /// Whitespace is removed as its own run, punctuation one symbol at a time,
    /// and words never cross `maximumCount` or a punctuation boundary.
    public static func deletionCount(
        contextBeforeInput: String,
        maximumCount: Int = 64,
        leadingEdgeMayBeTruncated: Bool = false
    ) -> Int {
        let limit = max(1, maximumCount)
        let suffix = Array(contextBeforeInput.suffix(limit))
        guard let last = suffix.last else { return 0 }
        let sourceMayBeTruncated = leadingEdgeMayBeTruncated
            || contextBeforeInput.count >= limit

        if last.isWhitespace {
            let count = suffix.reversed().prefix(while: \.isWhitespace).count
            return count == suffix.count && sourceMayBeTruncated ? 1 : count
        }
        if isWordCharacter(last) {
            let count = suffix.reversed().prefix(while: isWordCharacter).count
            return count == suffix.count && sourceMayBeTruncated ? 1 : count
        }
        return 1
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "’"
    }
}
