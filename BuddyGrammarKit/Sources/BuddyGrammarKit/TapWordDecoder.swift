import Foundation

/// One position in a word-sized tap lattice. The literal and per-tap resolved
/// keys remain explicit so a caller can always recover either conservative
/// path after whole-word ranking.
public struct TapWordLatticeTap: Equatable, Sendable {
    public let literalKey: Character
    public let resolvedKey: Character
    public let candidates: [TypingCandidate]

    public init(
        literalKey: Character,
        resolvedKey: Character,
        candidates: [TypingCandidate]
    ) {
        self.literalKey = literalKey
        self.resolvedKey = resolvedKey
        self.candidates = candidates
    }

    public init(decision: TypingDecision) {
        self.init(
            literalKey: decision.receipt.tap.literalKey,
            resolvedKey: decision.key,
            candidates: decision.candidates
        )
    }
}

/// A whole-word hypothesis. Scores are useful for deterministic ordering;
/// confidence is normalized over the bounded set returned by the decoder.
public struct TapWordCandidate: Equatable, Sendable {
    public let word: String
    public let score: Double
    public let confidence: Double
    public let isLiteralPath: Bool
    public let isResolvedPath: Bool

    public init(
        word: String,
        score: Double,
        confidence: Double,
        isLiteralPath: Bool,
        isResolvedPath: Bool
    ) {
        self.word = word
        self.score = score
        self.confidence = confidence
        self.isLiteralPath = isLiteralPath
        self.isResolvedPath = isResolvedPath
    }
}

/// Result of ranking a word-sized lattice. `margin` is the normalized
/// confidence gap between the first and second candidates. It is evidence,
/// not an autocorrection decision; policy remains with the caller.
public struct TapWordDecodingResult: Equatable, Sendable {
    public let literalWord: String
    public let resolvedWord: String
    public let candidates: [TapWordCandidate]
    public let margin: Double

    public init(
        literalWord: String,
        resolvedWord: String,
        candidates: [TapWordCandidate],
        margin: Double
    ) {
        self.literalWord = literalWord
        self.resolvedWord = resolvedWord
        self.candidates = candidates
        self.margin = margin
    }

    fileprivate static let empty = Self(
        literalWord: "",
        resolvedWord: "",
        candidates: [],
        margin: 0
    )
}

/// Deterministic, bounded beam search over adjacent per-key substitutions.
/// It owns no mutable history and persists no taps or text.
public struct TapWordDecoder: Sendable {
    public static let maximumTaps = 32
    public static let maximumCandidatesPerTap = 5
    public static let maximumBeamWidth = 48
    public static let maximumResults = 8

    private let lexicon: WordFrequencyLexicon
    private static let anchorConfidenceFloor = 0.015
    private static let comparisonEpsilon = 0.000_000_001

    /// Number of letter-key samples expected for a visible word. Display-only
    /// apostrophes are removed and diacritics are folded to QWERTY geometry.
    public static func expectedTapCount(for visibleWord: String) -> Int? {
        WordTokenNormalizer.tapGeometry(for: visibleWord)?.count
    }

    public static func hasExactKeyboardOwnership(
        _ taps: [TapWordLatticeTap],
        visibleWord: String
    ) -> Bool {
        guard let geometry = WordTokenNormalizer.tapGeometry(for: visibleWord),
              taps.count == geometry.count else { return false }
        let literalPath = String(taps.map(\.literalKey)).lowercased()
        let resolvedPath = String(taps.map(\.resolvedKey)).lowercased()
        return geometry == literalPath || geometry == resolvedPath
    }

    public init(lexicon: WordFrequencyLexicon = .shared) {
        self.lexicon = lexicon
    }

    public func decode(
        _ taps: [TapWordLatticeTap],
        previousWord: String? = nil,
        languageCode: String? = nil,
        limit: Int = 5
    ) -> TapWordDecodingResult {
        guard !taps.isEmpty, taps.count <= Self.maximumTaps else {
            return .empty
        }

        var optionRows: [[Option]] = []
        var literalCharacters: [Character] = []
        var resolvedCharacters: [Character] = []
        optionRows.reserveCapacity(taps.count)
        literalCharacters.reserveCapacity(taps.count)
        resolvedCharacters.reserveCapacity(taps.count)

        for tap in taps {
            guard let literal = Self.normalizedASCII(tap.literalKey),
                  let options = options(for: tap, normalizedLiteral: literal) else {
                return .empty
            }
            let resolved = Self.safeResolvedKey(
                tap.resolvedKey,
                literalKey: tap.literalKey,
                normalizedLiteral: literal
            )
            literalCharacters.append(tap.literalKey)
            resolvedCharacters.append(resolved)
            optionRows.append(options)
        }

        let literalWord = String(literalCharacters)
        let resolvedWord = String(resolvedCharacters)
        var beam = [Path(word: "", spatialLogScore: 0)]

        for options in optionRows {
            var expanded: [Path] = []
            expanded.reserveCapacity(beam.count * options.count)
            for path in beam {
                for option in options {
                    expanded.append(
                        Path(
                            word: path.word + String(option.key),
                            spatialLogScore: path.spatialLogScore + log(option.probability)
                        )
                    )
                }
            }
            expanded.sort(by: Self.pathRanksBefore)
            beam = Array(expanded.prefix(Self.maximumBeamWidth))
        }

        var pathsByWord: [String: Path] = [:]
        for path in beam {
            Self.insert(path, into: &pathsByWord)
        }
        Self.insert(
            forcedPath(word: literalWord, rows: optionRows),
            into: &pathsByWord
        )
        Self.insert(
            forcedPath(word: resolvedWord, rows: optionRows),
            into: &pathsByWord
        )

        let requiredWords = Set([literalWord, resolvedWord])
        var scoredByWord: [String: ScoredPath] = [:]
        func insertScored(_ candidate: ScoredPath) {
            guard let existing = scoredByWord[candidate.path.word] else {
                scoredByWord[candidate.path.word] = candidate
                return
            }
            if Self.scoredPathRanksBefore(candidate, existing) {
                scoredByWord[candidate.path.word] = candidate
            }
        }
        for path in pathsByWord.values {
            if let match = lexicon.match(
                for: path.word,
                languageCode: languageCode
            ) {
                let displayWord = Self.matchingCase(match.display, to: path.word)
                insertScored(
                    ScoredPath(
                        path: Path(
                            word: displayWord,
                            spatialLogScore: path.spatialLogScore
                        ),
                        score: path.spatialLogScore
                            + languageScore(
                                for: match,
                                previousWord: previousWord,
                                languageCode: languageCode
                            ),
                        isLiteral: displayWord == literalWord,
                        isResolved: displayWord == resolvedWord
                    )
                )
                // Canonical accents and apostrophes are extra lexical
                // hypotheses; conservative literal/resolved anchors remain
                // available byte-for-byte for undo and fallback.
                if !requiredWords.contains(path.word) || displayWord == path.word {
                    continue
                }
            }
            insertScored(
                ScoredPath(
                    path: path,
                    score: path.spatialLogScore
                        + outOfVocabularyScore(languageCode: languageCode),
                    isLiteral: path.word == literalWord,
                    isResolved: path.word == resolvedWord
                )
            )
        }
        var scored = Array(scoredByWord.values)
        scored.sort(by: Self.scoredPathRanksBefore)

        let requestedCount = max(requiredWords.count, min(max(limit, 1), Self.maximumResults))
        var selected = Array(scored.prefix(requestedCount))
        for word in requiredWords where !selected.contains(where: { $0.path.word == word }) {
            guard let forced = scored.first(where: { $0.path.word == word }) else { continue }
            if selected.count < requestedCount {
                selected.append(forced)
            } else if let removableIndex = selected.lastIndex(where: {
                !requiredWords.contains($0.path.word)
            }) {
                selected[removableIndex] = forced
            }
        }
        selected.sort(by: Self.scoredPathRanksBefore)

        guard let maximumScore = selected.first?.score, maximumScore.isFinite else {
            return Self.literalFallback(literalWord: literalWord, resolvedWord: resolvedWord)
        }
        let exponentials = selected.map { exp(($0.score - maximumScore) / 1.15) }
        let total = exponentials.reduce(0, +)
        guard total.isFinite, total > 0 else {
            return Self.literalFallback(literalWord: literalWord, resolvedWord: resolvedWord)
        }

        let candidates = zip(selected, exponentials).map { scored, exponential in
            TapWordCandidate(
                word: scored.path.word,
                score: scored.score,
                confidence: exponential / total,
                isLiteralPath: scored.isLiteral,
                isResolvedPath: scored.isResolved
            )
        }
        let firstConfidence = candidates.first?.confidence ?? 0
        let secondConfidence = candidates.dropFirst().first?.confidence ?? 0
        return TapWordDecodingResult(
            literalWord: literalWord,
            resolvedWord: resolvedWord,
            candidates: candidates,
            margin: max(0, min(1, firstConfidence - secondConfidence))
        )
    }

    private func options(
        for tap: TapWordLatticeTap,
        normalizedLiteral: Character
    ) -> [Option]? {
        let literalKey = Self.render(normalizedLiteral, like: tap.literalKey)
        let resolvedKey = Self.safeResolvedKey(
            tap.resolvedKey,
            literalKey: tap.literalKey,
            normalizedLiteral: normalizedLiteral
        )
        let normalizedResolved = Self.normalizedASCII(resolvedKey) ?? normalizedLiteral
        var weights: [Character: Double] = [:]

        // Reading only a bounded prefix avoids doing unbounded work on a
        // malformed lattice. Literal and resolved anchors are added below.
        for candidate in tap.candidates.prefix(Self.maximumCandidatesPerTap * 3) {
            guard candidate.confidence.isFinite,
                  candidate.confidence > 0,
                  let normalizedKey = Self.normalizedASCII(candidate.key),
                  normalizedKey == normalizedLiteral
                    || QwertyKeyLayout.distance(normalizedLiteral, normalizedKey)
                        <= QwertyKeyLayout.neighborDistance else {
                continue
            }
            weights[normalizedKey] = max(weights[normalizedKey, default: 0], candidate.confidence)
        }
        weights[normalizedLiteral] = max(
            weights[normalizedLiteral, default: 0],
            Self.anchorConfidenceFloor
        )
        weights[normalizedResolved] = max(
            weights[normalizedResolved, default: 0],
            Self.anchorConfidenceFloor
        )

        var ranked = weights.map { key, weight in
            WeightedKey(
                normalizedKey: key,
                renderedKey: Self.render(key, like: tap.literalKey),
                weight: weight,
                isLiteral: key == normalizedLiteral,
                isResolved: key == normalizedResolved
            )
        }
        ranked.sort(by: Self.weightedKeyRanksBefore)

        let required = Set([normalizedLiteral, normalizedResolved])
        var selected = Array(ranked.prefix(Self.maximumCandidatesPerTap))
        for key in required where !selected.contains(where: { $0.normalizedKey == key }) {
            guard let forced = ranked.first(where: { $0.normalizedKey == key }) else { continue }
            if let index = selected.lastIndex(where: { !required.contains($0.normalizedKey) }) {
                selected[index] = forced
            }
        }
        selected.sort(by: Self.weightedKeyRanksBefore)

        let total = selected.reduce(0) { $0 + $1.weight }
        guard total.isFinite, total > 0 else { return nil }
        return selected.map {
            Option(
                key: $0.normalizedKey == normalizedLiteral ? literalKey : $0.renderedKey,
                probability: max($0.weight / total, 0.000_000_001)
            )
        }
    }

    private func forcedPath(word: String, rows: [[Option]]) -> Path {
        var spatialLogScore = 0.0
        for (character, options) in zip(word, rows) {
            let normalized = Self.normalizedASCII(character)
            let probability = options.first {
                Self.normalizedASCII($0.key) == normalized
            }?.probability ?? Self.anchorConfidenceFloor
            spatialLogScore += log(max(probability, 0.000_000_001))
        }
        return Path(word: word, spatialLogScore: spatialLogScore)
    }

    private func languageScore(
        for match: WordFrequencyLexicon.Match,
        previousWord: String?,
        languageCode: String?
    ) -> Double {
        let normalized = match.display.lowercased()
        var score = max(-0.2, 0.9 - 0.25 * log10(Double(match.rank) + 1))

        if Self.isEnglish(languageCode), let previousWord {
            let predictions = NextWordPredictor.predictions(
                after: previousWord,
                languageCode: languageCode,
                limit: 3
            ).map { $0.lowercased() }
            if let index = predictions.firstIndex(of: normalized) {
                score += [0.9, 0.55, 0.3][index]
            }
        }
        return score
    }

    private func outOfVocabularyScore(languageCode: String?) -> Double {
        lexicon.supports(languageCode: languageCode) ? -0.75 : 0
    }

    private static func safeResolvedKey(
        _ key: Character,
        literalKey: Character,
        normalizedLiteral: Character
    ) -> Character {
        guard let normalized = normalizedASCII(key),
              normalized == normalizedLiteral
                || QwertyKeyLayout.distance(normalizedLiteral, normalized)
                    <= QwertyKeyLayout.neighborDistance else {
            return literalKey
        }
        return render(normalized, like: literalKey)
    }

    private static func normalizedASCII(_ character: Character) -> Character? {
        let normalized = String(character).lowercased()
        guard normalized.utf8.count == 1,
              let byte = normalized.utf8.first,
              (97...122).contains(byte) else {
            return nil
        }
        return Character(normalized)
    }

    private static func render(_ normalized: Character, like literal: Character) -> Character {
        let literalString = String(literal)
        if literalString == literalString.uppercased(),
           literalString != literalString.lowercased() {
            return Character(String(normalized).uppercased())
        }
        return normalized
    }

    private static func matchingCase(_ word: String, to typed: String) -> String {
        if typed.count > 1,
           typed.contains(where: \.isLetter),
           typed.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return word.uppercased()
        }
        guard typed.first?.isUppercase == true,
              let first = word.first else {
            return word
        }
        return first.uppercased() + word.dropFirst()
    }

    private static func isEnglish(_ languageCode: String?) -> Bool {
        guard let languageCode else { return false }
        let normalized = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
        return normalized.split(separator: "-", maxSplits: 1).first == "en"
    }

    private static func insert(_ path: Path, into paths: inout [String: Path]) {
        if let existing = paths[path.word], existing.spatialLogScore >= path.spatialLogScore {
            return
        }
        paths[path.word] = path
    }

    private static func literalFallback(
        literalWord: String,
        resolvedWord: String
    ) -> TapWordDecodingResult {
        TapWordDecodingResult(
            literalWord: literalWord,
            resolvedWord: resolvedWord,
            candidates: [
                TapWordCandidate(
                    word: literalWord,
                    score: 0,
                    confidence: 1,
                    isLiteralPath: true,
                    isResolvedPath: literalWord == resolvedWord
                ),
            ],
            margin: 1
        )
    }

    private static func pathRanksBefore(_ lhs: Path, _ rhs: Path) -> Bool {
        if abs(lhs.spatialLogScore - rhs.spatialLogScore) > comparisonEpsilon {
            return lhs.spatialLogScore > rhs.spatialLogScore
        }
        return lhs.word < rhs.word
    }

    private static func weightedKeyRanksBefore(_ lhs: WeightedKey, _ rhs: WeightedKey) -> Bool {
        if abs(lhs.weight - rhs.weight) > comparisonEpsilon {
            return lhs.weight > rhs.weight
        }
        if lhs.isLiteral != rhs.isLiteral { return lhs.isLiteral }
        if lhs.isResolved != rhs.isResolved { return lhs.isResolved }
        return String(lhs.normalizedKey) < String(rhs.normalizedKey)
    }

    private static func scoredPathRanksBefore(_ lhs: ScoredPath, _ rhs: ScoredPath) -> Bool {
        if abs(lhs.score - rhs.score) > comparisonEpsilon {
            return lhs.score > rhs.score
        }
        if lhs.isLiteral != rhs.isLiteral { return lhs.isLiteral }
        if lhs.isResolved != rhs.isResolved { return lhs.isResolved }
        return lhs.path.word < rhs.path.word
    }
}

private extension TapWordDecoder {
    struct Option: Sendable {
        let key: Character
        let probability: Double
    }

    struct WeightedKey: Sendable {
        let normalizedKey: Character
        let renderedKey: Character
        let weight: Double
        let isLiteral: Bool
        let isResolved: Bool
    }

    struct Path: Sendable {
        let word: String
        let spatialLogScore: Double
    }

    struct ScoredPath: Sendable {
        let path: Path
        let score: Double
        let isLiteral: Bool
        let isResolved: Bool
    }
}
