import Foundation

/// A spelling correction proposed directly from the bundled frequency lexicon.
public struct FuzzyCorrection: Equatable, Sendable {
    public let display: String
    /// Weighted edit distance between the typed word and the entry geometry
    /// (0 means the geometries match exactly, e.g. restoring an apostrophe
    /// or an accent that QWERTY geometry does not carry).
    public let distance: Double
    public let rank: Int
}

/// Proposes corrections from the bundled frequency lexicon without relying on
/// the platform spell checker.
///
/// Entries and queries are canonicalized to lowercase ASCII "geometry" (the
/// same normalization used for tap decoding), which makes apostrophe and
/// accent restoration fall out of ordinary edit-distance matching: typing
/// "dont" matches the geometry of "don’t" exactly, and "perche" sits one
/// substitution away from "perché". Candidates are verified with the same
/// weighted Damerau-Levenshtein metric the platform-candidate path uses, so
/// QWERTY-adjacent typos stay cheap while unrelated edits are rejected.
///
/// The scan is a flat pass over precomputed ASCII byte arrays. For the bundled
/// vocabulary sizes this stays in the tens-of-microseconds range on recent
/// hardware, which keeps it safe on the keystroke hot path.
public struct FuzzySpellingEngine: Sendable {
    private struct Entry {
        let display: String
        let geometryBytes: [UInt8]
        let rank: Int
    }

    private let entriesByLanguage: [String: [Entry]]
    private let lexicon: WordFrequencyLexicon

    public init(lexicon: WordFrequencyLexicon = .shared) {
        var entries: [String: [Entry]] = [:]
        for language in ["en", "it"] where lexicon.supports(languageCode: language) {
            let matches = lexicon.matches(languageCode: language).map { match in
                Entry(
                    display: match.display,
                    geometryBytes: Array(match.geometry.utf8),
                    rank: match.rank
                )
            }
            // Grouped by length so a lookup only visits the ±2-character
            // window the acceptance thresholds can ever admit.
            entries[language] = matches.sorted { $0.geometryBytes.count < $1.geometryBytes.count }
        }
        self.entriesByLanguage = entries
        self.lexicon = lexicon
    }

    /// Corrections for `typedWord`, best first: ascending weighted distance,
    /// then ascending frequency rank for deterministic ties.
    public func corrections(
        for typedWord: String,
        languageCode: String?,
        limit: Int
    ) -> [FuzzyCorrection] {
        guard limit > 0,
              typedWord.count >= 2,
              let queryGeometry = Self.canonicalGeometry(for: typedWord),
              !queryGeometry.isEmpty,
              let entries = entriesByLanguage[
                  LanguageSupport.primaryCode(for: languageCode)
              ] else {
            return []
        }
        // The query must be plain ASCII letters after canonicalization; mixed
        // scripts would silently distort the byte-based distance metric.
        guard queryGeometry.allSatisfy({ (97...122).contains($0) }) else {
            return []
        }

        let maximumLengthDelta = queryGeometry.count >= 6 ? 2 : 1
        let minimumLength = max(2, queryGeometry.count - maximumLengthDelta)
        let maximumLength = queryGeometry.count + maximumLengthDelta
        let windowStart = entries.firstIndex {
            $0.geometryBytes.count >= minimumLength
        } ?? entries.endIndex

        var matches: [FuzzyCorrection] = []
        var scratch = LocalWordCorrector.DistanceScratch(
            previousRow: [Double](repeating: 0, count: 33),
            currentRow: [Double](repeating: 0, count: 33),
            twoRowsBack: [Double](repeating: 0, count: 33)
        )
        let queryLength = queryGeometry.count
        for entry in entries[windowStart...] {
            let candidateLength = entry.geometryBytes.count
            if candidateLength > maximumLength { break }
            let longest = max(candidateLength, queryLength)
            // Insertions/deletions cost 0.9 each, so this length gap already
            // exceeds what the threshold could accept — skip without a DP.
            let bound = Double(candidateLength - queryLength) * 0.9 / Double(longest)
            if bound > LocalWordCorrector.acceptanceThreshold(forLength: longest) {
                continue
            }
            let threshold = LocalWordCorrector.acceptanceThreshold(
                forLength: max(candidateLength, queryLength)
            )
            let distance = LocalWordCorrector.weightedASCIIDistance(
                from: queryGeometry,
                to: entry.geometryBytes,
                scratch: &scratch
            )
            guard distance <= threshold else { continue }
            matches.append(
                FuzzyCorrection(display: entry.display, distance: distance, rank: entry.rank)
            )
        }

        matches.sort { lhs, rhs in
            if abs(lhs.distance - rhs.distance) > 0.000_001 {
                return lhs.distance < rhs.distance
            }
            return lhs.rank < rhs.rank
        }
        return Array(matches.prefix(limit))
    }

    /// Canonical lowercase ASCII geometry for a typed word, mirroring the
    /// lexicon's own normalization: diacritics folded, apostrophes stripped.
    static func canonicalGeometry(for word: String) -> [UInt8]? {
        let canonical = word
            .lowercased(with: Locale(identifier: "it_IT"))
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
            .filter { $0 != "’" && $0 != "'" }
        guard !canonical.isEmpty else { return nil }
        let bytes = Array(canonical.utf8)
        return bytes.allSatisfy { (97...122).contains($0) } ? bytes : nil
    }
}
