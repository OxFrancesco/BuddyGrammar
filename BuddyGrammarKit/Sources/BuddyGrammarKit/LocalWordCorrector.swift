import Foundation

public enum LocalWordCorrector {
    public static func bestCorrection(
        for typedWord: String,
        candidates: [String]
    ) -> String? {
        let source = typedWord.lowercased()
        guard source.count >= 2 else { return nil }
        let maximumLengthDelta = source.count >= 6 ? 2 : 1
        var seen = Set<String>()
        var best: RankedCandidate?

        for (index, candidate) in candidates.enumerated() {
            guard !candidate.isEmpty,
                  abs(candidate.count - source.count) <= maximumLengthDelta else {
                continue
            }
            let normalized = candidate.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            if normalized == source { return nil }
            let ranked = RankedCandidate(
                word: candidate,
                distance: normalizedDistance(from: source, to: normalized),
                index: index
            )
            guard ranked.distance <= acceptanceThreshold(
                forLength: max(source.count, candidate.count)
            ) else {
                continue
            }
            if best.map({ ranked.isPreferred(over: $0) }) ?? true {
                best = ranked
            }
        }

        guard let best else { return nil }
        return matchingCapitalization(of: typedWord, appliedTo: best.word)
    }

    private static func normalizedDistance(from source: String, to target: String) -> Double {
        let lhs = Array(source)
        let rhs = Array(target)
        guard !lhs.isEmpty, !rhs.isEmpty else { return 1 }

        var twoRowsBack = Array(repeating: 0.0, count: rhs.count + 1)
        var previousRow = (0...rhs.count).map { Double($0) * 0.9 }

        for sourceIndex in 1...lhs.count {
            var currentRow = Array(repeating: 0.0, count: rhs.count + 1)
            currentRow[0] = Double(sourceIndex) * 0.9
            for targetIndex in 1...rhs.count {
                let substitution = previousRow[targetIndex - 1]
                    + substitutionCost(lhs[sourceIndex - 1], rhs[targetIndex - 1])
                let deletion = previousRow[targetIndex] + 0.9
                let insertion = currentRow[targetIndex - 1] + 0.9
                var best = min(substitution, deletion, insertion)

                if sourceIndex > 1,
                   targetIndex > 1,
                   lhs[sourceIndex - 1] == rhs[targetIndex - 2],
                   lhs[sourceIndex - 2] == rhs[targetIndex - 1] {
                    best = min(best, twoRowsBack[targetIndex - 2] + 0.45)
                }
                currentRow[targetIndex] = best
            }
            twoRowsBack = previousRow
            previousRow = currentRow
        }

        return previousRow[rhs.count] / Double(max(lhs.count, rhs.count))
    }

    private struct RankedCandidate {
        let word: String
        let distance: Double
        let index: Int

        func isPreferred(over other: Self) -> Bool {
            if abs(distance - other.distance) > 0.0001 { return distance < other.distance }
            if word.count != other.word.count { return word.count < other.word.count }
            return index < other.index
        }
    }

    private static func substitutionCost(_ lhs: Character, _ rhs: Character) -> Double {
        guard lhs != rhs else { return 0 }
        guard let lhsPosition = keyPositions[lhs],
              let rhsPosition = keyPositions[rhs] else {
            return 1
        }
        let horizontal = lhsPosition.x - rhsPosition.x
        let vertical = lhsPosition.y - rhsPosition.y
        return hypot(horizontal, vertical) <= 1.3 ? 0.45 : 1
    }

    private static func acceptanceThreshold(forLength length: Int) -> Double {
        switch length {
        case ...3: 0.2
        case 4...5: 0.34
        default: 0.4
        }
    }

    private static func matchingCapitalization(of source: String, appliedTo correction: String) -> String {
        if source == source.uppercased(), source.rangeOfCharacter(from: .letters) != nil {
            return correction.uppercased()
        }
        guard source.first?.isUppercase == true, let first = correction.first else {
            return correction
        }
        return first.uppercased() + correction.dropFirst()
    }

    private static let keyPositions: [Character: (x: Double, y: Double)] = {
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
