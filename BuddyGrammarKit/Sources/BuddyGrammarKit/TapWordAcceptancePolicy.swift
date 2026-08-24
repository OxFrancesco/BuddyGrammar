import Foundation

/// Shared production thresholds for presenting versus automatically applying
/// a tap-lattice replacement. Keeping this policy in the core decoder prevents
/// iOS and Android controller call sites from drifting.
public enum TapWordAcceptancePolicy: String, Sendable {
    case suggestion
    case automatic

    public var minimumConfidence: Double {
        switch self {
        case .suggestion: 0.38
        case .automatic: 0.50
        }
    }

    public var minimumMargin: Double {
        switch self {
        case .suggestion: 0.08
        case .automatic: 0.18
        }
    }

    public func acceptedCandidate(
        from result: TapWordDecodingResult
    ) -> TapWordCandidate? {
        guard let best = result.candidates.first,
              best.confidence >= minimumConfidence,
              result.margin >= minimumMargin,
              best.word.caseInsensitiveCompare(result.literalWord) != .orderedSame else {
            return nil
        }
        return best
    }
}
