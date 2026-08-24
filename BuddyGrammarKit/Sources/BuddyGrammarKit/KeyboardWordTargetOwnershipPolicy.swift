import Foundation

public enum KeyboardWordTargetOwnershipPolicy {
    /// A proxy suffix is a complete word only when its preceding boundary is
    /// visible, or when the keyboard owns an exact tap for every target letter.
    public static func isCompleteTarget(
        contextBeforeInput: String,
        target: String,
        hasExactKeyboardOwnership: Bool
    ) -> Bool {
        guard !target.isEmpty,
              contextBeforeInput.hasSuffix(target) else { return false }
        if hasExactKeyboardOwnership { return true }
        guard contextBeforeInput.count > target.count,
              let precedingCharacter = contextBeforeInput
                  .dropLast(target.count)
                  .last else {
            return false
        }
        return !WordTokenNormalizer.isWordCharacter(precedingCharacter)
    }
}
