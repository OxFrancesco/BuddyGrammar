import CoreGraphics
import Foundation

/// QWERTY key centers in a normalized coordinate space where adjacent keys in
/// a row are 1 apart and rows are 1 apart, with the middle and bottom rows
/// offset like a physical keyboard.
public enum QwertyKeyLayout {
    public static let neighborDistance = 1.3

    public static func position(of character: Character) -> (x: Double, y: Double)? {
        positions[Character(character.lowercased())]
    }

    public static func center(of character: Character) -> CGPoint? {
        position(of: character).map { CGPoint(x: $0.x, y: $0.y) }
    }

    public static func distance(_ lhs: Character, _ rhs: Character) -> Double {
        guard let a = position(of: lhs), let b = position(of: rhs) else {
            return .infinity
        }
        return hypot(a.x - b.x, a.y - b.y)
    }

    static func nearestKey(to point: CGPoint, maximumDistance: Double = 0.8) -> Character? {
        positions
            .map { key, center in
                (key, hypot(center.x - point.x, center.y - point.y))
            }
            .filter { $0.1 <= maximumDistance }
            .min { $0.1 < $1.1 }?
            .0
    }

    private static let positions: [Character: (x: Double, y: Double)] = {
        let rows: [(String, Double)] = [
            ("qwertyuiop", 0),
            ("asdfghjkl", 0.25),
            ("zxcvbnm", 0.75),
        ]
        var positions: [Character: (x: Double, y: Double)] = [:]
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, character) in row.0.enumerated() {
                positions[character] = (Double(columnIndex) + row.1, Double(rowIndex))
            }
        }
        return positions
    }()
}

/// A monotonic swipe sample in normalized key-space. Milliseconds are used
/// explicitly so shared Swift/Kotlin conformance traces have the same unit.
public struct SwipePathSample: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let timestampMilliseconds: Double

    public init(x: Double, y: Double, timestampMilliseconds: Double) {
        self.x = x
        self.y = y
        self.timestampMilliseconds = timestampMilliseconds
    }

    public init(point: CGPoint, timestampMilliseconds: Double) {
        self.init(
            x: point.x,
            y: point.y,
            timestampMilliseconds: timestampMilliseconds
        )
    }

    fileprivate var point: CGPoint { CGPoint(x: x, y: y) }
}

public struct SwipeDwellConfiguration: Equatable, Sendable {
    public let minimumMilliseconds: Double
    public let minimumSamples: Int
    public let maximumDriftKeyUnits: Double

    public init(
        minimumMilliseconds: Double,
        minimumSamples: Int,
        maximumDriftKeyUnits: Double
    ) {
        self.minimumMilliseconds = minimumMilliseconds
        self.minimumSamples = minimumSamples
        self.maximumDriftKeyUnits = maximumDriftKeyUnits
    }

    /// Mirrors keyboard catalog v1. Native catalog loaders can inject a newer
    /// validated configuration without changing recognition callers.
    public static let contractV1 = Self(
        minimumMilliseconds: 180,
        minimumSamples: 3,
        maximumDriftKeyUnits: 0.42
    )
}

public struct SwipeCandidate: Equatable, Sendable {
    public let word: String
    public let confidence: Double

    public init(word: String, confidence: Double) {
        self.word = word
        self.confidence = confidence
    }
}

public enum SwipeAbstentionReason: String, Equatable, Sendable {
    case tooShort
    case invalidSamples
    case noCandidate
    case lowConfidence
    case ambiguous
}

public struct SwipeRecognitionResult: Equatable, Sendable {
    public let candidates: [SwipeCandidate]
    public let acceptedCandidate: SwipeCandidate?
    public let confidence: Double
    public let margin: Double
    public let abstentionReason: SwipeAbstentionReason?

    public var abstained: Bool { acceptedCandidate == nil }

    fileprivate init(
        candidates: [SwipeCandidate],
        acceptedCandidate: SwipeCandidate?,
        confidence: Double,
        margin: Double,
        abstentionReason: SwipeAbstentionReason?
    ) {
        self.candidates = candidates
        self.acceptedCandidate = acceptedCandidate
        self.confidence = confidence
        self.margin = margin
        self.abstentionReason = abstentionReason
    }

    fileprivate static func abstaining(_ reason: SwipeAbstentionReason) -> Self {
        Self(
            candidates: [],
            acceptedCandidate: nil,
            confidence: 0,
            margin: 0,
            abstentionReason: reason
        )
    }
}

/// SHARK²-style gesture recognizer for swipe typing.
///
/// The finger path (in key-space coordinates) is resampled to a fixed number
/// of equidistant points and compared against each candidate word's ideal
/// path through its key centers on two channels: absolute location, and
/// translation/scale-invariant shape. Channel distances are blended with a
/// word-frequency prior and an optional previous-word context boost.
public struct SwipeTypingEngine: Sendable {
    private struct Entry: Sendable {
        let word: String
        let rank: Int
        let languageCode: String?
        let centers: [CGPoint]
        let repeatedLetters: [Character: Int]
        let pathLength: Double
        let firstCenter: CGPoint
        let lastCenter: CGPoint
    }

    private struct WordSource {
        let word: String
        let rank: Int
        let languageCode: String?
    }

    private struct ScoredEntry {
        let word: String
        let score: Double
    }

    private let entries: [Entry]
    private let dwellConfiguration: SwipeDwellConfiguration
    private static let sampleCount = 32
    private static let anchorTolerance = 1.6
    private static let rejectionScore = 0.62
    private static let recognitionScoreLimit = 0.78
    private static let minimumConfidence = 0.50
    private static let minimumMargin = 0.03

    public init(
        extraWords: [String] = [],
        dwellConfiguration: SwipeDwellConfiguration = .contractV1
    ) {
        let lexicon = WordFrequencyLexicon.shared
        var sources: [WordSource] = []
        for languageCode in ["en", "it"] {
            sources.append(contentsOf: lexicon.words(languageCode: languageCode).enumerated().map {
                WordSource(
                    word: $0.element,
                    rank: $0.offset,
                    languageCode: languageCode
                )
            })
        }
        var seen = Set(sources.map(\.word))
        for extra in extraWords {
            guard let normalized = SwipeWordNormalizer.normalize(extra),
                  seen.insert(normalized.display).inserted else { continue }
            sources.append(
                WordSource(word: normalized.display, rank: 400, languageCode: nil)
            )
        }
        self.init(sources: sources, dwellConfiguration: dwellConfiguration)
    }

    /// Deterministic lexicon initializer used by language-pack loaders and
    /// cross-platform conformance tests. `words` are language-neutral while
    /// `languageWords` are considered only for the requested base language.
    public init(
        words: [String],
        languageWords: [String: [String]] = [:],
        dwellConfiguration: SwipeDwellConfiguration = .contractV1
    ) {
        var sources = words.enumerated().map {
            WordSource(word: $0.element, rank: $0.offset, languageCode: nil)
        }
        for languageCode in languageWords.keys.sorted() {
            let baseRank = sources.count
            sources.append(contentsOf: (languageWords[languageCode] ?? []).enumerated().map {
                WordSource(
                    word: $0.element,
                    rank: baseRank + $0.offset,
                    languageCode: Self.baseLanguage(languageCode)
                )
            })
        }
        self.init(sources: sources, dwellConfiguration: dwellConfiguration)
    }

    private init(
        sources: [WordSource],
        dwellConfiguration: SwipeDwellConfiguration
    ) {
        self.dwellConfiguration = dwellConfiguration
        var seen = Set<String>()
        entries = sources.compactMap { source in
            guard let form = SwipeWordNormalizer.normalize(source.word),
                  !form.geometry.isEmpty,
                  form.geometry.allSatisfy({ QwertyKeyLayout.position(of: $0) != nil }) else {
                return nil
            }
            let word = form.display
            guard seen.insert("\(source.languageCode ?? "*")|\(word)").inserted else {
                return nil
            }
            var centers: [CGPoint] = []
            var repeatedLetters: [Character: Int] = [:]
            var lastLetter: Character?
            for letter in form.geometry where letter != lastLetter {
                guard let center = QwertyKeyLayout.center(of: letter) else { return nil }
                centers.append(center)
                lastLetter = letter
            }
            lastLetter = nil
            for letter in form.geometry {
                if letter == lastLetter {
                    repeatedLetters[letter, default: 0] += 1
                }
                lastLetter = letter
            }
            guard let first = centers.first, let last = centers.last else { return nil }
            return Entry(
                word: word,
                rank: source.rank,
                languageCode: source.languageCode,
                centers: centers,
                repeatedLetters: repeatedLetters,
                pathLength: Self.length(of: centers),
                firstCenter: first,
                lastCenter: last
            )
        }
    }

    /// Convenience for tests and callers that only have a key trace: builds a
    /// path through the traced keys' centers.
    public func candidates(
        for trace: [Character],
        limit: Int = 3,
        previousWord: String? = nil
    ) -> [String] {
        let path = trace.compactMap(QwertyKeyLayout.center(of:))
        return candidates(forKeySpacePath: path, limit: limit, previousWord: previousWord)
    }

    /// Returns the best-matching words for a finger path expressed in
    /// key-space coordinates (1 unit = 1 key width), most likely first.
    public func candidates(
        forKeySpacePath path: [CGPoint],
        limit: Int = 3,
        previousWord: String? = nil
    ) -> [String] {
        scoredCandidates(
            path: path,
            repeatedLetters: nil,
            limit: limit,
            previousWord: previousWord,
            // This legacy geometry-only API historically used the bundled
            // English list. Locale-aware production callers use `recognize`.
            languageCode: "en"
        )
            .filter { $0.score <= Self.rejectionScore }
            .map(\.word)
    }

    /// Rich timed recognition Interface. Candidate confidences and the top-two
    /// margin are always returned when ranking succeeds; callers commit only
    /// `acceptedCandidate`, preserving conservative abstention.
    public func recognize(
        samples: [SwipePathSample],
        limit: Int = 3,
        previousWord: String? = nil,
        languageCode: String? = nil
    ) -> SwipeRecognitionResult {
        guard samples.count >= 2, limit > 0 else {
            return .abstaining(.tooShort)
        }
        guard Self.valid(samples: samples) else {
            return .abstaining(.invalidSamples)
        }

        let path = samples.map(\.point)
        let repeatedLetters = Self.repeatedLetterEvidence(
            in: samples,
            configuration: dwellConfiguration
        )
        let scored = scoredCandidates(
            path: path,
            repeatedLetters: repeatedLetters,
            limit: limit,
            previousWord: previousWord,
            languageCode: languageCode
        ).filter { $0.score <= Self.recognitionScoreLimit }
        guard !scored.isEmpty else {
            return .abstaining(.noCandidate)
        }

        let candidates = scored.map {
            SwipeCandidate(word: $0.word, confidence: Self.confidence(for: $0.score))
        }
        let confidence = candidates[0].confidence
        let margin = candidates.count > 1
            ? max(0, confidence - candidates[1].confidence)
            : confidence
        let reason: SwipeAbstentionReason?
        if confidence < Self.minimumConfidence {
            reason = .lowConfidence
        } else if margin < Self.minimumMargin {
            reason = .ambiguous
        } else {
            reason = nil
        }
        return SwipeRecognitionResult(
            candidates: candidates,
            acceptedCandidate: reason == nil ? candidates.first : nil,
            confidence: confidence,
            margin: margin,
            abstentionReason: reason
        )
    }

    private func scoredCandidates(
        path: [CGPoint],
        repeatedLetters: [Character: Int]?,
        limit: Int,
        previousWord: String?,
        languageCode: String?
    ) -> [ScoredEntry] {
        guard path.count >= 2, limit > 0,
              let start = path.first, let end = path.last else {
            return []
        }

        let requestedLanguage = languageCode.map(Self.baseLanguage)
        let eligibleEntries = entries.filter { entry in
            guard let requestedLanguage else { return true }
            return entry.languageCode == nil || entry.languageCode == requestedLanguage
        }
        let sampledPath = Self.resample(path, count: Self.sampleCount)
        let sampledShape = Self.shapeNormalized(sampledPath)
        let pathLength = Self.length(of: path)
        let vocabularySize = max(eligibleEntries.count, 1)
        let continuations = previousWord
            .flatMap { NextWordPredictor.bigrams[$0.lowercased()] } ?? []

        var bestByWord: [String: Double] = [:]
        for entry in eligibleEntries {
            let startDistance = Self.distance(entry.firstCenter, start)
            let endDistance = Self.distance(entry.lastCenter, end)
            guard startDistance <= Self.anchorTolerance,
                  endDistance <= Self.anchorTolerance,
                  abs(log((entry.pathLength + 0.5) / (pathLength + 0.5))) <= log(2.3) else {
                continue
            }

            let idealPath = Self.resample(entry.centers, count: Self.sampleCount)
            let location = Self.meanDistance(sampledPath, idealPath) / 3
            let shape = Self.meanDistance(sampledShape, Self.shapeNormalized(idealPath)) * 2
            let rankScore = log(1 + Double(entry.rank)) / log(1 + Double(vocabularySize))

            var score = 0.40 * min(location, 1.5)
                + 0.32 * min(shape, 1.5)
                + 0.18 * rankScore
                + 0.05 * (startDistance + endDistance)
            if let repeatedLetters {
                score += Self.repeatedLetterScore(
                    expected: entry.repeatedLetters,
                    observed: repeatedLetters
                )
            }
            if continuations.contains(entry.word) {
                score -= 0.10
            }
            bestByWord[entry.word] = min(bestByWord[entry.word] ?? .infinity, score)
        }

        let scored = bestByWord.map {
            ScoredEntry(word: $0.key, score: $0.value)
        }
        let sorted = scored.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.word < rhs.word : lhs.score < rhs.score
        }
        return Array(sorted.prefix(limit))
    }

    private static func repeatedLetterScore(
        expected: [Character: Int],
        observed: [Character: Int]
    ) -> Double {
        var score = 0.0
        for key in Set(expected.keys).union(observed.keys) {
            let expectedCount = expected[key, default: 0]
            let observedCount = observed[key, default: 0]
            let matched = min(expectedCount, observedCount)
            let missing = max(0, expectedCount - observedCount)
            let unexpected = max(0, observedCount - expectedCount)
            score -= 0.12 * Double(matched)
            score += 0.18 * Double(missing)
            score += 0.16 * Double(unexpected)
        }
        return score
    }

    private static func confidence(for score: Double) -> Double {
        let value = 1 / (1 + exp(6 * (score - 0.45)))
        return min(1, max(0, value))
    }

    private static func baseLanguage(_ languageCode: String) -> String {
        languageCode
            .lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? languageCode.lowercased()
    }

    private static func valid(samples: [SwipePathSample]) -> Bool {
        var previousTimestamp = -Double.infinity
        for sample in samples {
            guard sample.x.isFinite,
                  sample.y.isFinite,
                  sample.timestampMilliseconds.isFinite,
                  sample.timestampMilliseconds >= previousTimestamp else {
                return false
            }
            previousTimestamp = sample.timestampMilliseconds
        }
        return true
    }

    private static func repeatedLetterEvidence(
        in samples: [SwipePathSample],
        configuration: SwipeDwellConfiguration
    ) -> [Character: Int] {
        var runs: [(key: Character, samples: [SwipePathSample])] = []
        for sample in samples {
            guard let key = QwertyKeyLayout.nearestKey(to: sample.point) else { continue }
            if runs.last?.key == key {
                runs[runs.count - 1].samples.append(sample)
            } else {
                runs.append((key, [sample]))
            }
        }

        var evidence: [Character: Int] = [:]
        for run in runs {
            guard let first = run.samples.first, let last = run.samples.last,
                  run.samples.count >= configuration.minimumSamples,
                  last.timestampMilliseconds - first.timestampMilliseconds
                    >= configuration.minimumMilliseconds else {
                continue
            }
            let maximumDrift = run.samples.map {
                hypot($0.x - first.x, $0.y - first.y)
            }.max() ?? .infinity
            guard maximumDrift <= configuration.maximumDriftKeyUnits else { continue }
            evidence[run.key, default: 0] += 1
        }
        return evidence
    }

    // MARK: - Geometry

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func length(of points: [CGPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += distance(points[index - 1], points[index])
        }
        return total
    }

    /// Resamples a polyline into `count` equidistant points.
    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard let first = points.first else { return [] }
        let total = length(of: points)
        guard points.count > 1, total > 0 else {
            return Array(repeating: first, count: count)
        }

        let interval = total / Double(count - 1)
        var result: [CGPoint] = [first]
        var accumulated = 0.0
        var previous = first

        for point in points.dropFirst() {
            var segment = distance(previous, point)
            var segmentStart = previous
            while accumulated + segment >= interval, result.count < count {
                let ratio = (interval - accumulated) / segment
                let sample = CGPoint(
                    x: segmentStart.x + ratio * (point.x - segmentStart.x),
                    y: segmentStart.y + ratio * (point.y - segmentStart.y)
                )
                result.append(sample)
                segment = accumulated + segment - interval
                accumulated = 0
                segmentStart = sample
            }
            accumulated += segment
            previous = point
        }

        while result.count < count {
            result.append(points[points.count - 1])
        }
        return result
    }

    /// Translation- and scale-invariant form of a path: centered on its
    /// centroid and scaled by its bounding box.
    private static func shapeNormalized(_ points: [CGPoint]) -> [CGPoint] {
        guard !points.isEmpty else { return points }
        let count = Double(points.count)
        let centroid = CGPoint(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let scale = max(maxX - minX, maxY - minY, 0.01)
        return points.map {
            CGPoint(x: ($0.x - centroid.x) / scale, y: ($0.y - centroid.y) / scale)
        }
    }

    private static func meanDistance(_ lhs: [CGPoint], _ rhs: [CGPoint]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        var total = 0.0
        for index in lhs.indices {
            total += distance(lhs[index], rhs[index])
        }
        return total / Double(lhs.count)
    }
}
