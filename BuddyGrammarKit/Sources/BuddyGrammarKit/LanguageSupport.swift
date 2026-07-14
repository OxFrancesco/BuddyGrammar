import Foundation

/// Shared normalization for language-scoped text intelligence.
public enum LanguageSupport {
    public static let defaultPrimaryCode = "en"

    /// Returns a canonical primary language code, grouping regional variants
    /// and common ISO-639-3 detector output into the same local model scope.
    public static func primaryCode(for languageCode: String?) -> String {
        let primary = languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first?
            .lowercased() ?? ""
        guard (2...8).contains(primary.count),
              primary.allSatisfy(\.isLetter) else {
            return defaultPrimaryCode
        }
        return iso639ThreeToOne[primary] ?? primary
    }

    public static func usesEnglishPriors(languageCode: String?) -> Bool {
        primaryCode(for: languageCode) == defaultPrimaryCode
    }

    private static let iso639ThreeToOne: [String: String] = [
        "ara": "ar",
        "deu": "de",
        "eng": "en",
        "fra": "fr",
        "hin": "hi",
        "ita": "it",
        "jpn": "ja",
        "kor": "ko",
        "nld": "nl",
        "pol": "pl",
        "por": "pt",
        "rus": "ru",
        "spa": "es",
        "tur": "tr",
        "ukr": "uk",
        "zho": "zh",
    ]
}
