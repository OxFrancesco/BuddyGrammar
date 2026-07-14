import Foundation

/// Frequency-ordered English lexicon backed by the bundled swipe vocabulary.
/// Used to rank prefix completions by how common a word actually is, instead
/// of the alphabetical order UITextChecker returns.
public struct WordFrequencyLexicon: Sendable {
    public static let shared = WordFrequencyLexicon()

    private let words: [String]
    private let ranks: [String: Int]

    public init() {
        var words: [String] = []
        if let url = Bundle.module.url(forResource: "SwipeVocabulary", withExtension: "txt"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            words = contents.split(separator: "\n").map(String.init)
        }
        self.words = words
        self.ranks = Dictionary(
            words.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Words starting with `prefix`, most frequent first.
    public func completions(forPrefix prefix: String, limit: Int) -> [String] {
        guard limit > 0, !prefix.isEmpty else { return [] }
        let normalized = prefix.lowercased()
        var results: [String] = []
        for word in words where word.count > normalized.count && word.hasPrefix(normalized) {
            results.append(word)
            if results.count == limit { break }
        }
        return results
    }

    /// Lower is more frequent; nil when the word is not in the lexicon.
    public func rank(of word: String) -> Int? {
        ranks[word.lowercased()]
    }
}
