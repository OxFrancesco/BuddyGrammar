@testable import BuddyGrammar
import XCTest

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultGrammarProfileIsPresent() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: suite)

        XCTAssertEqual(store.profiles.first?.id, PromptProfile.grammarProfileID)
        XCTAssertEqual(store.profiles.first?.hotkey, PromptProfile.defaultGrammarHotkey)
    }

    func testProfilesPersistOrdering() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: suite)

        let addedID = store.addProfile()
        store.moveProfile(id: addedID, direction: .up)

        let reloaded = SettingsStore(defaults: suite)
        XCTAssertEqual(reloaded.profiles.first?.id, addedID)
    }

    func testGrammarProfileMigratesLegacyShortcut() throws {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)

        let legacyProfile = PromptProfile(
            id: PromptProfile.grammarProfileID,
            name: "Grammar",
            instruction: PromptProfile.grammar.instruction,
            hotkey: PromptProfile.legacyGrammarHotkey,
            isEnabled: true,
            isBuiltIn: true
        )

        let data = try JSONEncoder().encode([legacyProfile])
        suite.set(data, forKey: "BuddyGrammar.profiles")

        let store = SettingsStore(defaults: suite)
        XCTAssertEqual(store.profiles.first?.hotkey, PromptProfile.defaultGrammarHotkey)
    }

    func testSettingsLoadWhenLegacyOverlayMotionModeIsPresent() throws {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)

        let legacyJSON = """
        {
          "outputMode": "copyToClipboard",
          "launchAtLogin": true,
          "overlayMotionMode": "full",
          "hasCompletedOnboarding": true
        }
        """

        suite.set(Data(legacyJSON.utf8), forKey: "BuddyGrammar.settings")

        let store = SettingsStore(defaults: suite)
        XCTAssertEqual(store.appSettings.outputMode, .copyToClipboard)
        XCTAssertTrue(store.appSettings.launchAtLogin)
        XCTAssertTrue(store.appSettings.hasCompletedOnboarding)
    }
}
