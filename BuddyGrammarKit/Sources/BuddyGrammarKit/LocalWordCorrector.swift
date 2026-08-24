import Foundation

public enum LocalWordCorrector {
    public static func bestCorrection(
        for typedWord: String,
        candidates: [String]
    ) -> String? {
        guard let best = rankedCorrections(
            for: typedWord,
            candidates: candidates,
            limit: 1
        ).first else { return nil }
        return matchingCapitalization(of: typedWord, appliedTo: best.word)
    }

    /// Candidates that pass the acceptance thresholds for `typedWord`, best
    /// first. `contextAdjustment` may return a negative bonus that influences
    /// ordering only; it can never rescue a candidate past its distance
    /// threshold, so context re-ranks without loosening correctness gates.
    public static func rankedCorrections(
        for typedWord: String,
        candidates: [String],
        limit: Int,
        contextAdjustment: ((String) -> Double)? = nil
    ) -> [(word: String, distance: Double)] {
        guard limit > 0 else { return [] }
        let source = typedWord.lowercased()
        guard source.count >= 2 else { return [] }
        let maximumLengthDelta = source.count >= 6 ? 2 : 1
        var seen = Set<String>()
        var accepted: [RankedCandidate] = []

        for (index, candidate) in candidates.enumerated() {
            guard !candidate.isEmpty,
                  abs(candidate.count - source.count) <= maximumLengthDelta else {
                continue
            }
            let normalized = candidate.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            // An exact candidate means the typed word is already a known
            // spelling; no correction should be proposed at all.
            if normalized == source { return [] }
            let ranked = RankedCandidate(
                word: candidate,
                distance: normalizedDistance(from: source, to: normalized),
                index: index,
                adjustment: contextAdjustment?(normalized) ?? 0
            )
            guard ranked.distance <= acceptanceThreshold(
                forLength: max(source.count, candidate.count)
            ) else {
                continue
            }
            accepted.append(ranked)
        }

        let sorted = accepted.sorted { $0.isPreferred(over: $1) }
        return sorted.prefix(limit).map { ($0.word, $0.distance) }
    }

    private static func normalizedDistance(from source: String, to target: String) -> Double {
        weightedDistance(
            Array(source),
            Array(target)
        ) { substitutionCost($0, $1) }
    }

    /// Weighted Damerau-Levenshtein distance over lowercase ASCII letters,
    /// normalized by the longer length. QWERTY-adjacent substitutions and
    /// transpositions cost 0.45; other substitutions 1; insert/delete 0.9.
    /// Callers must guarantee both inputs are ASCII letters (see
    /// ``FuzzySpellingEngine/canonicalGeometry(for:)``).
    public static func weightedASCIIDistance(
        from source: [UInt8],
        to target: [UInt8]
    ) -> Double {
        var scratch = DistanceScratch(
            previousRow: [Double](repeating: 0, count: target.count + 1),
            currentRow: [Double](repeating: 0, count: target.count + 1),
            twoRowsBack: [Double](repeating: 0, count: target.count + 1)
        )
        return weightedASCIIDistance(from: source, to: target, scratch: &scratch)
    }

    /// Reusable DP buffers so batched lookups (one per keystroke pause) never
    /// allocate per candidate.
    public struct DistanceScratch {
        var previousRow: [Double]
        var currentRow: [Double]
        var twoRowsBack: [Double]

        init(previousRow: [Double], currentRow: [Double], twoRowsBack: [Double]) {
            self.previousRow = previousRow
            self.currentRow = currentRow
            self.twoRowsBack = twoRowsBack
        }
    }

    public static func weightedASCIIDistance(
        from source: [UInt8],
        to target: [UInt8],
        scratch: inout DistanceScratch
    ) -> Double {
        guard !source.isEmpty, !target.isEmpty else { return 1 }
        let requiredLength = target.count + 1
        let costs = flatSubstitutionCosts

        func ensure(_ row: inout [Double]) {
            if row.count < requiredLength {
                row = [Double](repeating: 0, count: requiredLength)
            }
        }
        ensure(&scratch.previousRow)
        ensure(&scratch.currentRow)
        ensure(&scratch.twoRowsBack)

        let width = requiredLength
        for column in 0..<width {
            scratch.previousRow[column] = Double(column) * 0.9
        }

        for sourceIndex in 1...source.count {
            scratch.currentRow[0] = Double(sourceIndex) * 0.9
            let sourceBase = Int(source[sourceIndex - 1] - 97) * 26
            let canTranspose = sourceIndex > 1
            for targetIndex in 1..<width {
                let substitution = scratch.previousRow[targetIndex - 1]
                    + costs[sourceBase + Int(target[targetIndex - 1] - 97)]
                let deletion = scratch.previousRow[targetIndex] + 0.9
                let insertion = scratch.currentRow[targetIndex - 1] + 0.9
                var best = substitution < deletion ? substitution : deletion
                if insertion < best { best = insertion }

                if canTranspose,
                   targetIndex > 1,
                   source[sourceIndex - 1] == target[targetIndex - 2],
                   source[sourceIndex - 2] == target[targetIndex - 1] {
                    let transposition = scratch.twoRowsBack[targetIndex - 2] + 0.45
                    if transposition < best { best = transposition }
                }
                scratch.currentRow[targetIndex] = best
            }
            // Rotate rows for the next pass.
            for column in 0..<width {
                scratch.twoRowsBack[column] = scratch.previousRow[column]
                scratch.previousRow[column] = scratch.currentRow[column]
            }
        }

        return scratch.previousRow[target.count]
            / Double(max(source.count, target.count))
    }

    private static func weightedDistance<Element: Equatable>(
        _ lhs: [Element],
        _ rhs: [Element],
        substitutionCost: (Element, Element) -> Double
    ) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 1 }

        var twoRowsBack = Array(repeating: 0.0, count: rhs.count + 1)
        var previousRow = (0...rhs.count).map { Double($0) * 0.9 }

        for lhsIndex in 1...lhs.count {
            var currentRow = Array(repeating: 0.0, count: rhs.count + 1)
            currentRow[0] = Double(lhsIndex) * 0.9
            for rhsIndex in 1...rhs.count {
                let substitution = previousRow[rhsIndex - 1]
                    + substitutionCost(lhs[lhsIndex - 1], rhs[rhsIndex - 1])
                let deletion = previousRow[rhsIndex] + 0.9
                let insertion = currentRow[rhsIndex - 1] + 0.9
                var best = min(substitution, deletion, insertion)

                if lhsIndex > 1,
                   rhsIndex > 1,
                   lhs[lhsIndex - 1] == rhs[rhsIndex - 2],
                   lhs[lhsIndex - 2] == rhs[rhsIndex - 1] {
                    best = min(best, twoRowsBack[rhsIndex - 2] + 0.45)
                }
                currentRow[rhsIndex] = best
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
        let adjustment: Double

        /// Ordering key: adjusted distance first (context bonus participates),
        /// then raw distance, then shorter word, then candidate order.
        func isPreferred(over other: Self) -> Bool {
            let lhsKey = distance + adjustment
            let rhsKey = other.distance + other.adjustment
            if abs(lhsKey - rhsKey) > 0.000_001 { return lhsKey < rhsKey }
            if abs(distance - other.distance) > 0.000_001 { return distance < other.distance }
            if word.count != other.word.count { return word.count < other.word.count }
            return index < other.index
        }
    }

    private static func substitutionCost(_ lhs: Character, _ rhs: Character) -> Double {
        guard lhs != rhs else { return 0 }
        guard let lhsScalar = lhs.asciiValue,
              let rhsScalar = rhs.asciiValue,
              areQwertyNeighbors(lhsScalar, rhsScalar) else {
            return 1
        }
        return 0.45
    }

    /// Precomputed QWERTY substitution costs for ASCII letters, indexed by
    /// `(lhs - 97) * 26 + (rhs - 97)`, so the DP inner loop stays branch-light.
    private static let flatSubstitutionCosts: [Double] = {
        var costs = [Double](repeating: 1, count: 26 * 26)
        for lhs in 0..<26 {
            for rhs in 0..<26 {
                let cost: Double
                if lhs == rhs {
                    cost = 0
                } else if areQwertyNeighbors(UInt8(lhs + 97), UInt8(rhs + 97)) {
                    cost = 0.45
                } else {
                    cost = 1
                }
                costs[lhs * 26 + rhs] = cost
            }
        }
        return costs
    }()

    private static func areQwertyNeighbors(_ lhs: UInt8, _ rhs: UInt8) -> Bool {
        guard let lhsPosition = asciiKeyPositions[lhs],
              let rhsPosition = asciiKeyPositions[rhs] else {
            return false
        }
        let horizontal = (Double(lhsPosition.column) + lhsPosition.rowOffset)
            - (Double(rhsPosition.column) + rhsPosition.rowOffset)
        let vertical = Double(lhsPosition.row) - Double(rhsPosition.row)
        return hypot(horizontal, vertical) <= 1.3
    }

    static func acceptanceThreshold(forLength length: Int) -> Double {
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

    private static let asciiKeyPositions: [UInt8: (row: Int, column: Int, rowOffset: Double)] = {
        let rows: [(String, Int, Double)] = [
            ("qwertyuiop", 0, 0),
            ("asdfghjkl", 1, 0.25),
            ("zxcvbnm", 2, 0.75),
        ]
        var positions: [UInt8: (row: Int, column: Int, rowOffset: Double)] = [:]
        for (row, rowIndex, rowOffset) in rows {
            for (columnIndex, character) in row.utf8.enumerated() {
                positions[character] = (rowIndex, columnIndex, rowOffset)
            }
        }
        return positions
    }()
}
