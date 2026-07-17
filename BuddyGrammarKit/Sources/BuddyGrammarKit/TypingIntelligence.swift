import Foundation

public enum TypingPolicy: String, Codable, Equatable, Sendable {
    case literal
    case generic
    case personalizedReadOnly
    case personalizedLearning
    case practice
}

/// A tap expressed in the same normalized key-space used by
/// ``QwertyKeyLayout``: one horizontal unit is one key width and one vertical
/// unit is one keyboard row.
public struct TouchSample: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let literalKey: Character
    public let timestamp: TimeInterval

    public init(x: Double, y: Double, literalKey: Character, timestamp: TimeInterval) {
        self.x = x
        self.y = y
        self.literalKey = literalKey
        self.timestamp = timestamp
    }
}

/// Text available to the keyboard decoder. The suffix is bounded so a caller
/// cannot accidentally retain a document in a long-lived typing module.
public struct TypingContext: Equatable, Sendable {
    public static let maximumCharacterCount = 96

    public let rawText: String
    public let languageCode: String?

    public init(rawText: String, languageCode: String? = nil) {
        self.rawText = String(rawText.suffix(Self.maximumCharacterCount))
        self.languageCode = languageCode?.lowercased()
    }
}

public struct TypingCandidate: Equatable, Sendable {
    public let key: Character
    public let confidence: Double

    public init(key: Character, confidence: Double) {
        self.key = key
        self.confidence = confidence
    }
}

/// Opaque evidence needed to attach explicit feedback to the tap that
/// produced it. It intentionally contains no surrounding text.
public struct TypingDecisionReceipt: Equatable, Sendable {
    public let tap: TouchSample
    public let policy: TypingPolicy
    public let resolvedKey: Character

    public init(tap: TouchSample, policy: TypingPolicy, resolvedKey: Character) {
        self.tap = tap
        self.policy = policy
        self.resolvedKey = resolvedKey
    }
}

public struct TypingDecision: Equatable, Sendable {
    public let key: Character
    public let candidates: [TypingCandidate]
    public let confidence: Double
    public let adapted: Bool
    public let receipt: TypingDecisionReceipt
}

public enum TypingOutcomeSource: String, Codable, Equatable, Sendable {
    /// The app knew the requested practice target before the touch occurred.
    case practice
    /// The user rejected a result and explicitly typed its replacement.
    case retype
    /// A decoder-produced value. This source is never accepted as a label.
    case decoder
}

public enum TypingFeedback: Equatable, Sendable {
    case positive(intendedKey: Character)
    case rejection(correctedKey: Character?)
}

public struct TypingOutcome: Equatable, Sendable {
    public let receipt: TypingDecisionReceipt
    public let feedback: TypingFeedback
    public let source: TypingOutcomeSource

    public init(
        receipt: TypingDecisionReceipt,
        feedback: TypingFeedback,
        source: TypingOutcomeSource
    ) {
        self.receipt = receipt
        self.feedback = feedback
        self.source = source
    }

    public static func positive(
        receipt: TypingDecisionReceipt,
        intendedKey: Character,
        source: TypingOutcomeSource
    ) -> Self {
        Self(
            receipt: receipt,
            feedback: .positive(intendedKey: intendedKey),
            source: source
        )
    }

    public static func rejection(
        receipt: TypingDecisionReceipt,
        correctedKey: Character?,
        source: TypingOutcomeSource
    ) -> Self {
        Self(
            receipt: receipt,
            feedback: .rejection(correctedKey: correctedKey),
            source: source
        )
    }
}

public struct TypingKeyAggregate: Codable, Equatable, Sendable {
    public private(set) var sampleCount: Int
    public private(set) var meanX: Double
    public private(set) var meanY: Double

    public init(sampleCount: Int = 0, meanX: Double = 0, meanY: Double = 0) {
        self.sampleCount = max(0, min(sampleCount, Self.maximumSamples))
        self.meanX = meanX.isFinite ? meanX : 0
        self.meanY = meanY.isFinite ? meanY : 0
    }

    private static let maximumSamples = 512

    fileprivate mutating func record(x: Double, y: Double) {
        let boundedX = max(-0.45, min(x, 0.45))
        let boundedY = max(-0.45, min(y, 0.45))
        if sampleCount < Self.maximumSamples {
            sampleCount += 1
            let denominator = Double(sampleCount)
            meanX += (boundedX - meanX) / denominator
            meanY += (boundedY - meanY) / denominator
        } else {
            // A capped online window keeps the aggregate responsive without
            // retaining an unbounded event history.
            meanX += (boundedX - meanX) / Double(Self.maximumSamples)
            meanY += (boundedY - meanY) / Double(Self.maximumSamples)
        }
    }
}

/// Fixed-size, persistence-ready personalization state. It stores only
/// aggregate offsets and confusion counts—never taps, timestamps, or text.
public struct TypingProfile: Codable, Equatable, Sendable {
    public private(set) var explicitObservationCount: Int
    public private(set) var rejectionCount: Int
    public private(set) var keyOffsets: [String: TypingKeyAggregate]
    public private(set) var confusions: [String: Int]

    public init(
        explicitObservationCount: Int = 0,
        rejectionCount: Int = 0,
        keyOffsets: [String: TypingKeyAggregate] = [:],
        confusions: [String: Int] = [:]
    ) {
        self.explicitObservationCount = max(0, explicitObservationCount)
        self.rejectionCount = max(0, rejectionCount)
        self.keyOffsets = keyOffsets.filter {
            $0.key.count == 1 && QwertyKeyLayout.position(of: Character($0.key)) != nil
        }
        self.confusions = confusions.filter { $0.key.count == 3 }
    }

    fileprivate mutating func record(
        tap: TouchSample,
        intendedKey: Character,
        rejected: Bool
    ) {
        guard tap.x.isFinite,
              tap.y.isFinite,
              let intendedCenter = QwertyKeyLayout.position(of: intendedKey),
              QwertyKeyLayout.position(of: tap.literalKey) != nil,
              intendedKey == tap.literalKey
                || QwertyKeyLayout.distance(tap.literalKey, intendedKey)
                    <= QwertyKeyLayout.neighborDistance,
              hypot(tap.x - intendedCenter.x, tap.y - intendedCenter.y) <= 1.5 else {
            return
        }

        let key = String(intendedKey).lowercased()
        var aggregate = keyOffsets[key, default: TypingKeyAggregate()]
        aggregate.record(
            x: tap.x - intendedCenter.x,
            y: tap.y - intendedCenter.y
        )
        keyOffsets[key] = aggregate
        explicitObservationCount = min(explicitObservationCount + 1, 1_000_000)

        if rejected {
            rejectionCount = min(rejectionCount + 1, 1_000_000)
            if tap.literalKey != intendedKey {
                let confusion = "\(tap.literalKey)>\(intendedKey)".lowercased()
                confusions[confusion] = min(
                    confusions[confusion, default: 0] + 1,
                    10_000
                )
            }
        }
    }

    fileprivate mutating func recordRejection() {
        rejectionCount = min(rejectionCount + 1, 1_000_000)
    }
}

/// Resolves normalized taps while keeping dynamic hit regions, language
/// ranking, and personalization behind one small caller-facing seam.
public struct TypingIntelligence: Sendable {
    public let policy: TypingPolicy

    private let lexicon: WordFrequencyLexicon
    private var profile: TypingProfile
    private static let keys = Array("qwertyuiopasdfghjklzxcvbnm")
    private static let literalAnchorRadius = 0.28
    private static let spatialStandardDeviation = 0.43

    public init(
        profile: TypingProfile = TypingProfile(),
        policy: TypingPolicy = .generic
    ) {
        self.policy = policy
        self.profile = profile
        self.lexicon = .shared
    }

    public var snapshot: TypingProfile {
        profile
    }

    public mutating func observe(_ outcome: TypingOutcome) {
        guard policy.allowsProfileWrites,
              outcome.receipt.policy.allowsProfileWrites,
              outcome.source != .decoder else {
            return
        }

        switch outcome.feedback {
        case let .positive(intendedKey):
            profile.record(
                tap: outcome.receipt.tap,
                intendedKey: intendedKey,
                rejected: false
            )
        case let .rejection(correctedKey):
            if let correctedKey {
                profile.record(
                    tap: outcome.receipt.tap,
                    intendedKey: correctedKey,
                    rejected: true
                )
            } else {
                profile.recordRejection()
            }
        }
    }

    public func resolve(tap: TouchSample, context: TypingContext) -> TypingDecision {
        guard policy != .literal,
              tap.x.isFinite,
              tap.y.isFinite,
              let literalCenter = QwertyKeyLayout.position(of: tap.literalKey) else {
            return literalDecision(for: tap)
        }

        let literalDistance = hypot(tap.x - literalCenter.x, tap.y - literalCenter.y)
        guard literalDistance > Self.literalAnchorRadius else {
            return literalDecision(for: tap)
        }

        let candidateKeys = Self.keys.filter {
            $0 == tap.literalKey
                || QwertyKeyLayout.distance(tap.literalKey, $0)
                    <= QwertyKeyLayout.neighborDistance
        }
        guard !candidateKeys.isEmpty else {
            return literalDecision(for: tap)
        }

        let languageBoosts = languageBoosts(for: candidateKeys, context: context)
        let variance = Self.spatialStandardDeviation * Self.spatialStandardDeviation
        var scores = candidateKeys.compactMap { key -> (key: Character, score: Double)? in
            guard let center = expectedTouchCenter(for: key) else { return nil }
            let squaredDistance = pow(tap.x - center.x, 2) + pow(tap.y - center.y, 2)
            let spatialScore = -squaredDistance / (2 * variance)
            return (key, spatialScore + (languageBoosts[key] ?? 0))
        }
        guard !scores.isEmpty else {
            return literalDecision(for: tap)
        }

        scores.sort { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.000_001 {
                return lhs.score > rhs.score
            }
            if lhs.key == tap.literalKey { return true }
            if rhs.key == tap.literalKey { return false }
            return String(lhs.key) < String(rhs.key)
        }

        guard let best = scores.first, best.score.isFinite else {
            return literalDecision(for: tap)
        }
        let maximumScore = best.score
        let exponentials = scores.map { exp($0.score - maximumScore) }
        let total = exponentials.reduce(0, +)
        guard total.isFinite, total > 0 else {
            return literalDecision(for: tap)
        }
        let candidates = zip(scores, exponentials).map { scored, exponential in
            TypingCandidate(key: scored.key, confidence: exponential / total)
        }
        let chosen = candidates[0]
        return TypingDecision(
            key: chosen.key,
            candidates: candidates,
            confidence: chosen.confidence,
            adapted: chosen.key != tap.literalKey,
            receipt: TypingDecisionReceipt(
                tap: tap,
                policy: policy,
                resolvedKey: chosen.key
            )
        )
    }

    private func expectedTouchCenter(
        for key: Character
    ) -> (x: Double, y: Double)? {
        guard let fixedCenter = QwertyKeyLayout.position(of: key) else {
            return nil
        }
        guard policy.usesPersonalization,
              let aggregate = profile.keyOffsets[String(key).lowercased()],
              aggregate.sampleCount > 0 else {
            return fixedCenter
        }

        // The fixed QWERTY center is the population prior. Personal evidence
        // earns influence gradually and can never move the expected center by
        // more than 0.35 key widths/heights.
        let evidence = Double(aggregate.sampleCount)
        let shrinkage = min(0.85, evidence / (evidence + 8))
        let offsetX = max(-0.35, min(aggregate.meanX * shrinkage, 0.35))
        let offsetY = max(-0.35, min(aggregate.meanY * shrinkage, 0.35))
        return (fixedCenter.x + offsetX, fixedCenter.y + offsetY)
    }

    /// Applies a language prior only when English is explicitly selected and
    /// one continuation is materially stronger. Weak or tied evidence leaves
    /// the spatial/literal ordering untouched.
    private func languageBoosts(
        for candidates: [Character],
        context: TypingContext
    ) -> [Character: Double] {
        guard Self.isEnglish(context.languageCode) else { return [:] }
        let prefix = Self.currentASCIIWord(in: context.rawText)
        guard prefix.count >= 2 else { return [:] }

        let evidence = candidates.map { key -> (key: Character, evidence: Double) in
            let proposedPrefix = prefix + String(key)
            var value = 0.0
            if let rank = lexicon.rank(of: proposedPrefix) {
                value += 2 + Self.frequencyWeight(rank: rank)
            }
            for completion in lexicon.completions(forPrefix: proposedPrefix, limit: 3) {
                let rank = lexicon.rank(of: completion) ?? 10_000
                value += 0.35 + 0.45 * Self.frequencyWeight(rank: rank)
            }
            return (key, value)
        }
        .sorted { lhs, rhs in
            if abs(lhs.evidence - rhs.evidence) > 0.000_001 {
                return lhs.evidence > rhs.evidence
            }
            if lhs.key == candidates.first { return true }
            return String(lhs.key) < String(rhs.key)
        }

        guard let strongest = evidence.first else { return [:] }
        let runnerUp = evidence.dropFirst().first?.evidence ?? 0
        guard strongest.evidence >= 1,
              strongest.evidence - runnerUp >= 0.5 else {
            return [:]
        }
        let boost = min(1.35, 0.75 + 0.25 * (strongest.evidence - runnerUp))
        return [strongest.key: boost]
    }

    private static func frequencyWeight(rank: Int) -> Double {
        1 / (1 + log10(Double(max(rank, 0)) + 1))
    }

    private static func currentASCIIWord(in text: String) -> String {
        let suffix = text.lowercased().reversed().prefix { character in
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first else {
                return false
            }
            return (97...122).contains(scalar.value)
        }
        return String(suffix.reversed())
    }

    private static func isEnglish(_ languageCode: String?) -> Bool {
        guard let languageCode else { return false }
        let normalized = languageCode.replacingOccurrences(of: "_", with: "-")
        return normalized.split(separator: "-", maxSplits: 1).first == "en"
    }

    private func literalDecision(for tap: TouchSample) -> TypingDecision {
        let candidate = TypingCandidate(key: tap.literalKey, confidence: 1)
        return TypingDecision(
            key: tap.literalKey,
            candidates: [candidate],
            confidence: candidate.confidence,
            adapted: false,
            receipt: TypingDecisionReceipt(
                tap: tap,
                policy: policy,
                resolvedKey: tap.literalKey
            )
        )
    }
}

private extension TypingPolicy {
    var allowsProfileWrites: Bool {
        self == .personalizedLearning || self == .practice
    }

    var usesPersonalization: Bool {
        self == .personalizedReadOnly
            || self == .personalizedLearning
            || self == .practice
    }
}
