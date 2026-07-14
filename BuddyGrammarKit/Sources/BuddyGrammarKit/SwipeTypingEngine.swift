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
        let centers: [CGPoint]
        let pathLength: Double
        let firstCenter: CGPoint
        let lastCenter: CGPoint
    }

    private let entries: [Entry]
    private static let sampleCount = 32
    private static let anchorTolerance = 1.6
    private static let rejectionScore = 0.62

    public init(extraWords: [String] = []) {
        var words: [(word: String, rank: Int)] = []
        if let url = Bundle.module.url(forResource: "SwipeVocabulary", withExtension: "txt"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            words = contents
                .split(separator: "\n")
                .enumerated()
                .map { (String($0.element), $0.offset) }
        }
        var seen = Set(words.map(\.word))
        for extra in extraWords {
            let normalized = extra.lowercased()
            guard normalized.count >= 2,
                  normalized.allSatisfy({ QwertyKeyLayout.position(of: $0) != nil }),
                  seen.insert(normalized).inserted else { continue }
            words.append((normalized, 400))
        }

        entries = words.compactMap { word, rank in
            var centers: [CGPoint] = []
            var lastLetter: Character?
            for letter in word where letter != lastLetter {
                guard let center = QwertyKeyLayout.center(of: letter) else { return nil }
                centers.append(center)
                lastLetter = letter
            }
            guard let first = centers.first, let last = centers.last else { return nil }
            return Entry(
                word: word,
                rank: rank,
                centers: centers,
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
        guard path.count >= 2, limit > 0,
              let start = path.first, let end = path.last else {
            return []
        }

        let sampledPath = Self.resample(path, count: Self.sampleCount)
        let sampledShape = Self.shapeNormalized(sampledPath)
        let pathLength = Self.length(of: path)
        let vocabularySize = max(entries.count, 1)
        let continuations = previousWord
            .flatMap { NextWordPredictor.bigrams[$0.lowercased()] } ?? []

        var scored: [(word: String, score: Double)] = []
        for entry in entries {
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
            if continuations.contains(entry.word) {
                score -= 0.10
            }
            scored.append((entry.word, score))
        }

        return scored
            .filter { $0.score <= Self.rejectionScore }
            .sorted { $0.score < $1.score }
            .prefix(limit)
            .map(\.word)
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
