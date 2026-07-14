import Foundation

public enum LocalWordCorrector {
    public static func bestCorrection(
        for typedWord: String,
        candidates: [String]
    ) -> String? {
        let source = typedWord.lowercased()
        guard source.count >= 2 else { return nil }

        let ranked = candidates
            .lazy
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(typedWord) != .orderedSame }
            .map { candidate in
                let normalized = candidate.lowercased()
                return (candidate, normalizedDistance(from: source, to: normalized))
            }
            .filter { $0.1 <= acceptanceThreshold(forLength: max(source.count, $0.0.count)) }
            .sorted { lhs, rhs in
                if abs(lhs.1 - rhs.1) > 0.0001 { return lhs.1 < rhs.1 }
                return lhs.0.count < rhs.0.count
            }

        guard let best = ranked.first?.0 else { return nil }
        return matchingCapitalization(of: typedWord, appliedTo: best)
    }

    private static func normalizedDistance(from source: String, to target: String) -> Double {
        let lhs = Array(source)
        let rhs = Array(target)
        guard !lhs.isEmpty, !rhs.isEmpty else { return 1 }

        var matrix = Array(
            repeating: Array(repeating: 0.0, count: rhs.count + 1),
            count: lhs.count + 1
        )
        for index in 0...lhs.count { matrix[index][0] = Double(index) * 0.9 }
        for index in 0...rhs.count { matrix[0][index] = Double(index) * 0.9 }

        for sourceIndex in 1...lhs.count {
            for targetIndex in 1...rhs.count {
                let substitution = matrix[sourceIndex - 1][targetIndex - 1]
                    + substitutionCost(lhs[sourceIndex - 1], rhs[targetIndex - 1])
                let deletion = matrix[sourceIndex - 1][targetIndex] + 0.9
                let insertion = matrix[sourceIndex][targetIndex - 1] + 0.9
                var best = min(substitution, deletion, insertion)

                if sourceIndex > 1,
                   targetIndex > 1,
                   lhs[sourceIndex - 1] == rhs[targetIndex - 2],
                   lhs[sourceIndex - 2] == rhs[targetIndex - 1] {
                    best = min(best, matrix[sourceIndex - 2][targetIndex - 2] + 0.45)
                }
                matrix[sourceIndex][targetIndex] = best
            }
        }

        return matrix[lhs.count][rhs.count] / Double(max(lhs.count, rhs.count))
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
