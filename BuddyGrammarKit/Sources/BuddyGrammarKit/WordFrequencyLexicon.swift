import Foundation

/// Frequency-ordered language packs shared by tap decoding, swipe typing, and
/// static completion ranking. Each language is isolated: an English rank is
/// never consulted for an Italian session (or vice versa).
public struct WordFrequencyLexicon: Sendable {
    public struct Match: Equatable, Sendable {
        public let display: String
        public let geometry: String
        public let rank: Int

        public init(display: String, geometry: String, rank: Int) {
            self.display = display
            self.geometry = geometry
            self.rank = rank
        }
    }

    public static let shared = WordFrequencyLexicon()

    private let entriesByLanguage: [String: [Match]]
    private let matchesByLanguageAndGeometry: [String: [String: Match]]

    public init() {
        var languageWords: [String: [String]] = [:]
        for resource in [
            (languageId: "en", name: "SwipeVocabulary"),
            (languageId: "it", name: "SwipeVocabulary-it-v1"),
        ] {
            guard let url = Bundle.module.url(
                forResource: resource.name,
                withExtension: "txt"
            ),
            let source = try? String(contentsOf: url, encoding: .utf8),
            let words = try? SwipeLexicon.parse(source: source) else {
                continue
            }
            languageWords[resource.languageId] = words
        }
        self.init(languageWords: languageWords)
    }

    /// Deterministic injection seam for contract tests and future downloaded
    /// language packs. Invalid/non-canonical entries are ignored; production
    /// bundled sources are separately validated by the shared Bun contract.
    public init(languageWords: [String: [String]]) {
        var entries: [String: [Match]] = [:]
        var matches: [String: [String: Match]] = [:]
        for (rawLanguage, words) in languageWords {
            let language = LanguageSupport.primaryCode(for: rawLanguage)
            var seenDisplay = Set<String>()
            var ranked: [Match] = []
            var byGeometry: [String: Match] = [:]
            for word in words {
                guard let form = SwipeWordNormalizer.normalize(word),
                      seenDisplay.insert(form.display).inserted else {
                    continue
                }
                let entry = Match(
                    display: form.display,
                    geometry: form.geometry,
                    rank: ranked.count
                )
                ranked.append(entry)
                // Accent/elision variants may intentionally share geometry.
                // The language pack's rank is the deterministic tap spelling.
                if byGeometry[form.geometry] == nil {
                    byGeometry[form.geometry] = entry
                }
            }
            entries[language] = ranked
            matches[language] = byGeometry
        }
        entriesByLanguage = entries
        matchesByLanguageAndGeometry = matches
    }

    public func supports(languageCode: String?) -> Bool {
        entriesByLanguage[LanguageSupport.primaryCode(for: languageCode)] != nil
    }

    public func wordCount(languageCode: String?) -> Int {
        entriesByLanguage[LanguageSupport.primaryCode(for: languageCode)]?.count ?? 0
    }

    public func words(languageCode: String?) -> [String] {
        entriesByLanguage[LanguageSupport.primaryCode(for: languageCode)]?.map(\.display) ?? []
    }

    /// Canonical language-pack match for a typed display or ASCII geometry.
    public func match(for word: String, languageCode: String?) -> Match? {
        guard let geometry = Self.geometry(for: word) else { return nil }
        let language = LanguageSupport.primaryCode(for: languageCode)
        return matchesByLanguageAndGeometry[language]?[geometry]
    }

    /// Words starting with `prefix`, most frequent first. Diacritics and
    /// apostrophes do not participate in QWERTY geometry matching, while the
    /// returned spelling remains the canonical display form from the pack.
    public func completions(
        forPrefix prefix: String,
        languageCode: String?,
        limit: Int
    ) -> [String] {
        guard limit > 0,
              let prefixGeometry = Self.prefixGeometry(for: prefix),
              !prefixGeometry.isEmpty else {
            return []
        }
        let language = LanguageSupport.primaryCode(for: languageCode)
        let canonicalTyped = Self.canonicalDisplay(for: prefix)
        let requiresApostropheMatch = canonicalTyped.contains("’")
        var results: [String] = []
        for entry in entriesByLanguage[language] ?? [] {
            guard (requiresApostropheMatch
                    ? entry.display.hasPrefix(canonicalTyped)
                    : entry.geometry.hasPrefix(prefixGeometry)),
                  entry.geometry.count > prefixGeometry.count
                    || entry.display.caseInsensitiveCompare(canonicalTyped) != .orderedSame else {
                continue
            }
            results.append(entry.display)
            if results.count == limit { break }
        }
        return results
    }

    public func rank(of word: String, languageCode: String?) -> Int? {
        match(for: word, languageCode: languageCode)?.rank
    }

    // Compatibility APIs retain the historical English default.
    public func completions(forPrefix prefix: String, limit: Int) -> [String] {
        completions(forPrefix: prefix, languageCode: "en", limit: limit)
    }

    public func rank(of word: String) -> Int? {
        rank(of: word, languageCode: "en")
    }

    private static func geometry(for word: String) -> String? {
        SwipeWordNormalizer.normalize(word)?.geometry
    }

    private static func prefixGeometry(for prefix: String) -> String? {
        let canonical = canonicalDisplay(for: prefix)
        guard !canonical.isEmpty,
              canonical.contains(where: \.isLetter),
              canonical.allSatisfy({ $0.isLetter || $0 == "’" }) else {
            return nil
        }
        let geometry = canonical
            .folding(
                options: .diacriticInsensitive,
                locale: Locale(identifier: "it_IT")
            )
            .filter { $0 != "’" }
        return geometry.allSatisfy({ $0.isASCII && $0.isLowercase })
            ? geometry
            : nil
    }

    private static func canonicalDisplay(for word: String) -> String {
        word
            .lowercased(with: Locale(identifier: "it_IT"))
            .map { apostrophes.contains($0) ? Character("’") : $0 }
            .reduce(into: "") { $0.append($1) }
            .precomposedStringWithCanonicalMapping
    }

    private static let apostrophes: Set<Character> = ["'", "‘", "’", "ʼ", "＇"]
}
