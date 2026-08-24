import Foundation

/// A user-visible spelling paired with the ASCII QWERTY path used to score it.
struct SwipeWordForm: Equatable, Sendable {
    let display: String
    let geometry: String
}

/// Keeps Italian spelling separate from the 26-key geometry used by swipes.
enum SwipeWordNormalizer {
    static func normalize(_ word: String) -> SwipeWordForm? {
        let display = word
            .lowercased(with: italianLocale)
            .map { apostrophes.contains($0) ? canonicalApostrophe : $0 }
            .reduce(into: "") { $0.append($1) }
            .precomposedStringWithCanonicalMapping
        guard validDisplayWord(display) else { return nil }

        let geometry = display
            .folding(options: .diacriticInsensitive, locale: italianLocale)
            .filter { character in
                character != canonicalApostrophe
            }
        guard geometry.count >= 2,
              geometry.allSatisfy({ $0.isASCII && $0.isLowercase }) else {
            return nil
        }
        return SwipeWordForm(display: display, geometry: geometry)
    }

    private static func validDisplayWord(_ word: String) -> Bool {
        var sawLetter = false
        var previousWasApostrophe = false
        for scalar in word.unicodeScalars {
            if CharacterSet.lowercaseLetters.contains(scalar) {
                sawLetter = true
                previousWasApostrophe = false
            } else if scalar == canonicalApostrophe.unicodeScalars.first {
                guard sawLetter, !previousWasApostrophe else { return false }
                previousWasApostrophe = true
            } else {
                return false
            }
        }
        return sawLetter
    }

    private static let italianLocale = Locale(identifier: "it_IT")
    private static let canonicalApostrophe: Character = "’"
    private static let apostrophes: Set<Character> = ["'", "‘", "’", "ʼ", "＇"]
}
