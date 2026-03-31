import Foundation

struct PromptProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var instruction: String
    var hotkey: HotkeyDescriptor?
    var isEnabled: Bool
    var isBuiltIn: Bool

    static let grammarProfileID = UUID(uuidString: "B48FDF75-0C5D-4A96-B48D-29D160C6B470")!

    static let grammar = PromptProfile(
        id: grammarProfileID,
        name: "Grammar",
        instruction: """
        Fix grammar, spelling, punctuation, and capitalization only.
        Preserve the original language, wording, tone, and meaning as much as possible.
        Do not add explanations, quotes, prefixes, or suffixes.
        Return only the corrected text.
        """,
        hotkey: HotkeyDescriptor(keyCode: 5, modifiers: [.control, .option]),
        isEnabled: true,
        isBuiltIn: true
    )

    static func newCustomProfile() -> PromptProfile {
        PromptProfile(
            id: UUID(),
            name: "Custom Prompt",
            instruction: "Rewrite the selected text. Return only the final text.",
            hotkey: nil,
            isEnabled: false,
            isBuiltIn: false
        )
    }
}
