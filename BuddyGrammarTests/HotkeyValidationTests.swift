@testable import BuddyGrammar
import AppKit
import XCTest

@MainActor
final class HotkeyValidationTests: XCTestCase {
    func testDetectsDuplicateHotkeys() {
        let hotkey = HotkeyDescriptor(keyCode: 5, modifiers: [.control, .option])
        let profiles = [
            PromptProfile(
                id: UUID(),
                name: "One",
                instruction: "First",
                hotkey: hotkey,
                isEnabled: true,
                isBuiltIn: false
            ),
            PromptProfile(
                id: UUID(),
                name: "Two",
                instruction: "Second",
                hotkey: hotkey,
                isEnabled: true,
                isBuiltIn: false
            )
        ]

        XCTAssertTrue(SettingsStore.hasDuplicateHotkeys(in: profiles))
    }
}
