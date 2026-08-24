import Foundation

public enum BuddyRewriteIntent: String, CaseIterable, Identifiable, Sendable {
    case fix
    case shorten
    case clearer
    case friendly
    case formal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fix: "Fix"
        case .shorten: "Shorten"
        case .clearer: "Clearer"
        case .friendly: "Friendly"
        case .formal: "Formal"
        }
    }

    public func instruction(appendingTo base: String) -> String {
        let transformation = switch self {
        case .fix:
            "Fix only clear grammar, spelling, punctuation, and capitalization errors."
        case .shorten:
            "Make the text meaningfully shorter without removing important information."
        case .clearer:
            "Improve clarity and directness while preserving the meaning and factual claims."
        case .friendly:
            "Use a warm, friendly tone while preserving the meaning and factual claims."
        case .formal:
            "Use a polished, professional tone while preserving the meaning and factual claims."
        }
        return "\(base.trimmingCharacters(in: .whitespacesAndNewlines))\n\(transformation) Return only the replacement text."
    }
}

public struct ReviewableCorrectionProposal: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let intent: BuddyRewriteIntent
    public let originalText: String
    public let proposedText: String
    public let change: BoundedTextChange

    public init(
        id: UUID = UUID(),
        intent: BuddyRewriteIntent,
        originalText: String,
        proposedText: String
    ) {
        self.id = id
        self.intent = intent
        self.originalText = originalText
        self.proposedText = proposedText
        self.change = BoundedTextChange(original: originalText, proposed: proposedText)
    }

    public var hasChanges: Bool { originalText != proposedText }
}

/// A single bounded changed span suitable for a compact keyboard diff. The
/// editor snapshot remains authoritative when a proposal is accepted.
public struct BoundedTextChange: Equatable, Sendable {
    public let commonPrefix: String
    public let originalChangedText: String
    public let proposedChangedText: String
    public let commonSuffix: String

    public init(original: String, proposed: String) {
        guard original != proposed else {
            commonPrefix = original
            originalChangedText = ""
            proposedChangedText = ""
            commonSuffix = ""
            return
        }

        let originalCharacters = Array(original)
        let proposedCharacters = Array(proposed)
        var prefixCount = 0
        while prefixCount < min(originalCharacters.count, proposedCharacters.count),
              originalCharacters[prefixCount] == proposedCharacters[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < originalCharacters.count - prefixCount,
              suffixCount < proposedCharacters.count - prefixCount,
              originalCharacters[originalCharacters.count - suffixCount - 1]
                == proposedCharacters[proposedCharacters.count - suffixCount - 1] {
            suffixCount += 1
        }

        commonPrefix = String(originalCharacters.prefix(prefixCount))
        originalChangedText = String(
            originalCharacters.dropFirst(prefixCount).dropLast(suffixCount)
        )
        proposedChangedText = String(
            proposedCharacters.dropFirst(prefixCount).dropLast(suffixCount)
        )
        commonSuffix = suffixCount == 0
            ? ""
            : String(originalCharacters.suffix(suffixCount))
    }
}
