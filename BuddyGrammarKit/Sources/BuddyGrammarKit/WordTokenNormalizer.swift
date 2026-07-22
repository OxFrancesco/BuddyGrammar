import Foundation

/// Canonical word-boundary rules shared by context analysis, language-model
/// storage, and static completions. Curly U+2019 is the persisted/display
/// apostrophe; common keyboard/input variants are accepted at the boundary.
enum WordTokenNormalizer {
    static let canonicalApostrophe: Character = "’"
    static let apostrophes: Set<Character> = ["'", "‘", "’", "ʼ", "＇"]

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || apostrophes.contains(character)
    }

    static func canonicalized(_ text: String) -> String {
        text
            .map { apostrophes.contains($0) ? canonicalApostrophe : $0 }
            .reduce(into: "") { $0.append($1) }
            .precomposedStringWithCanonicalMapping
    }

    static func tapGeometry(for text: String) -> String? {
        let canonical = canonicalized(
            text.lowercased(with: Locale(identifier: "it_IT"))
        )
        guard !canonical.isEmpty,
              canonical.contains(where: \.isLetter),
              canonical.allSatisfy({ $0.isLetter || $0 == canonicalApostrophe }) else {
            return nil
        }
        let geometry = canonical
            .folding(
                options: .diacriticInsensitive,
                locale: Locale(identifier: "it_IT")
            )
            .filter { $0 != canonicalApostrophe }
        return geometry.allSatisfy({ $0.isASCII && $0.isLowercase })
            ? geometry
            : nil
    }
}
