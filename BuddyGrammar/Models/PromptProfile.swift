import Foundation

struct PromptProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var instruction: String
    var hotkey: HotkeyDescriptor?
    var isEnabled: Bool
    var isBuiltIn: Bool

    static let grammarProfileID = UUID(uuidString: "B48FDF75-0C5D-4A96-B48D-29D160C6B470")!
    static let legacyGrammarHotkey = HotkeyDescriptor(keyCode: 5, modifiers: [.control, .option])
    static let defaultStandardHotkey = HotkeyDescriptor(keyCode: 18, modifiers: [.command, .shift])
    static let standardInstruction = """
    Fix grammar, spelling, punctuation, and capitalization only.
    Preserve the original language, wording, tone, and meaning as much as possible.
    Do not add explanations, quotes, prefixes, or suffixes.
    Return only the corrected text.
    """
    static let legacyGrammarName = "Grammar"

    static let standard = PromptProfile(
        id: grammarProfileID,
        name: "Standard",
        instruction: standardInstruction,
        hotkey: defaultStandardHotkey,
        isEnabled: true,
        isBuiltIn: true
    )

    static func newCustomProfile() -> PromptProfile {
        PromptProfile(
            id: UUID(),
            name: "Custom Personality",
            instruction: "Rewrite the selected text. Return only the final text.",
            hotkey: nil,
            isEnabled: false,
            isBuiltIn: false
        )
    }

    var isStandard: Bool {
        id == Self.grammarProfileID && isBuiltIn
    }

    var usesLockedStandardContent: Bool {
        name == Self.standard.name && instruction == Self.standard.instruction
    }

    func matchesLegacyBuiltInDefinition() -> Bool {
        name == Self.legacyGrammarName && instruction == Self.standardInstruction
    }
}

enum PersonalityTemplate: String, CaseIterable, Identifiable {
    case formal
    case email
    case twitterPost
    case blankCustom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formal:
            "Formal"
        case .email:
            "Email"
        case .twitterPost:
            "Twitter Post"
        case .blankCustom:
            "Blank Custom"
        }
    }

    var prompt: String {
        switch self {
        case .formal:
            "Rewrite the selected text into a more formal, polished version while preserving its meaning. Return only the final text."
        case .email:
            "Rewrite the selected text into a clear, professional email. Keep it natural. Return only the final text."
        case .twitterPost:
            "Rewrite the selected text into a concise single Twitter/X-style post, under 280 characters when reasonably possible. Return only the final text."
        case .blankCustom:
            "Rewrite the selected text. Return only the final text."
        }
    }

    var suggestedHotkey: HotkeyDescriptor? {
        switch self {
        case .formal:
            HotkeyDescriptor(keyCode: 19, modifiers: [.command, .shift])
        case .email:
            HotkeyDescriptor(keyCode: 20, modifiers: [.command, .shift])
        case .twitterPost:
            HotkeyDescriptor(keyCode: 21, modifiers: [.command, .shift])
        case .blankCustom:
            nil
        }
    }

    func makeProfile(availableHotkeys: Set<HotkeyDescriptor>) -> PromptProfile {
        let hotkey = suggestedHotkey.flatMap { availableHotkeys.contains($0) ? $0 : nil }
        return PromptProfile(
            id: UUID(),
            name: title,
            instruction: prompt,
            hotkey: hotkey,
            isEnabled: hotkey != nil,
            isBuiltIn: false
        )
    }
}
