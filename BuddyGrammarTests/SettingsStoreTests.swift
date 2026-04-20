@testable import BuddyGrammar
import XCTest

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testFreshInstallSeedsStandardPersonality() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: suite)

        XCTAssertEqual(store.profiles.first?.id, PromptProfile.grammarProfileID)
        XCTAssertEqual(store.profiles.first?.name, "Standard")
        XCTAssertEqual(store.profiles.first?.hotkey, PromptProfile.defaultStandardHotkey)
        XCTAssertEqual(store.appSettings.rewriteProvider, .openRouter(modelID: OpenRouterModel.defaultID))
        XCTAssertEqual(store.appSettings.selectedLocalModel, .qwen3_4b_instruct_2507_4bit)
        XCTAssertTrue(store.appSettings.preloadLocalModelOnLaunch)
        XCTAssertEqual(store.appSettings.voiceProfileID, PromptProfile.grammarProfileID)
        XCTAssertEqual(store.appSettings.voiceLocaleIdentifier, Locale.autoupdatingCurrent.identifier)
        XCTAssertNil(store.appSettings.voiceHotkey)
    }

    func testStandardPersonalityStaysPinnedFirst() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: suite)

        let addedID = store.addProfile(template: .formal)
        store.moveProfile(id: addedID, direction: .up)

        let reloaded = SettingsStore(defaults: suite)
        XCTAssertEqual(reloaded.profiles.first?.id, PromptProfile.grammarProfileID)
        XCTAssertEqual(reloaded.profiles.dropFirst().first?.id, addedID)
    }

    func testUntouchedLegacyBuiltInBecomesStandardAndPreservesShortcut() throws {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)

        let legacyProfile = PromptProfile(
            id: PromptProfile.grammarProfileID,
            name: "Grammar",
            instruction: PromptProfile.standardInstruction,
            hotkey: PromptProfile.legacyGrammarHotkey,
            isEnabled: true,
            isBuiltIn: true
        )

        let data = try JSONEncoder().encode([legacyProfile])
        suite.set(data, forKey: "BuddyGrammar.profiles")

        let store = SettingsStore(defaults: suite)
        XCTAssertEqual(store.profiles.first?.name, "Standard")
        XCTAssertEqual(store.profiles.first?.hotkey, PromptProfile.legacyGrammarHotkey)
    }

    func testCustomizedBuiltInIsPreservedAsCustomAndStandardIsRestored() throws {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)

        let customizedBuiltIn = PromptProfile(
            id: PromptProfile.grammarProfileID,
            name: "My Voice",
            instruction: "Rewrite this in my voice.",
            hotkey: PromptProfile.legacyGrammarHotkey,
            isEnabled: true,
            isBuiltIn: true
        )

        let data = try JSONEncoder().encode([customizedBuiltIn])
        suite.set(data, forKey: "BuddyGrammar.profiles")

        let store = SettingsStore(defaults: suite)

        XCTAssertEqual(store.profiles.first?.name, "Standard")
        XCTAssertNil(store.profiles.first?.hotkey)
        XCTAssertFalse(store.profiles.first?.isEnabled ?? true)
        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertEqual(store.profiles[1].name, "My Voice")
        XCTAssertEqual(store.profiles[1].hotkey, PromptProfile.legacyGrammarHotkey)
        XCTAssertFalse(store.profiles[1].isBuiltIn)
    }

    func testFormalTemplateGetsSuggestedShortcutWhenAvailable() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: suite)

        let id = store.addProfile(template: .formal)
        let profile = store.profile(id: id)

        XCTAssertEqual(profile?.name, "Formal")
        XCTAssertEqual(profile?.hotkey, PersonalityTemplate.formal.suggestedHotkey)
        XCTAssertTrue(profile?.isEnabled ?? false)
    }

    func testFormalTemplateStartsWithoutShortcutWhenSuggestedSlotIsTaken() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: suite)

        var standard = store.profiles[0]
        standard.hotkey = PersonalityTemplate.formal.suggestedHotkey
        standard.isEnabled = true
        store.update(standard)

        let id = store.addProfile(template: .formal)
        let profile = store.profile(id: id)

        XCTAssertEqual(profile?.name, "Formal")
        XCTAssertNil(profile?.hotkey)
        XCTAssertFalse(profile?.isEnabled ?? true)
    }

    func testBlankCustomStartsWithoutShortcut() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: suite)

        let id = store.addProfile()
        let profile = store.profile(id: id)

        XCTAssertEqual(profile?.name, "Blank Custom")
        XCTAssertNil(profile?.hotkey)
        XCTAssertFalse(profile?.isEnabled ?? true)
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
        XCTAssertEqual(store.appSettings.rewriteProvider, .openRouter(modelID: OpenRouterModel.defaultID))
        XCTAssertEqual(store.appSettings.selectedLocalModel, .qwen3_4b_instruct_2507_4bit)
        XCTAssertTrue(store.appSettings.preloadLocalModelOnLaunch)
        XCTAssertEqual(store.appSettings.voiceProfileID, PromptProfile.grammarProfileID)
        XCTAssertEqual(store.appSettings.voiceLocaleIdentifier, Locale.autoupdatingCurrent.identifier)
        XCTAssertNil(store.appSettings.voiceHotkey)
    }

    func testSettingsDecodeLocalProviderDefaults() throws {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)

        let localSettingsJSON = """
        {
          "outputMode": "replaceSelection",
          "rewriteProvider": {
            "kind": "local",
            "modelID": "gemma4_e4b_it_mxfp8"
          },
          "selectedLocalModel": "gemma4_e4b_it_mxfp8",
          "preloadLocalModelOnLaunch": false,
          "voiceProfileID": "B48FDF75-0C5D-4A96-B48D-29D160C6B470",
          "voiceLocaleIdentifier": "en_US",
          "voiceHotkey": {
            "keyCode": 49,
            "modifiersRawValue": 1048576
          },
          "launchAtLogin": false,
          "hasCompletedOnboarding": true
        }
        """

        suite.set(Data(localSettingsJSON.utf8), forKey: "BuddyGrammar.settings")

        let store = SettingsStore(defaults: suite)
        XCTAssertEqual(store.appSettings.rewriteProvider, .local(modelID: .gemma4_e4b_it_mxfp8))
        XCTAssertEqual(store.appSettings.selectedLocalModel, .gemma4_e4b_it_mxfp8)
        XCTAssertFalse(store.appSettings.preloadLocalModelOnLaunch)
        XCTAssertEqual(store.appSettings.voiceProfileID, PromptProfile.grammarProfileID)
        XCTAssertEqual(store.appSettings.voiceLocaleIdentifier, "en_US")
        XCTAssertEqual(store.appSettings.voiceHotkey, HotkeyDescriptor(keyCode: 49, modifiers: [.command]))
    }

    func testSettingsDecodeLocalProviderFallsBackToProviderModelWhenSelectedModelIsMissing() throws {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)

        let localSettingsJSON = """
        {
          "rewriteProvider": {
            "kind": "local",
            "modelID": "gemma4_e4b_it_mxfp8"
          }
        }
        """

        suite.set(Data(localSettingsJSON.utf8), forKey: "BuddyGrammar.settings")

        let store = SettingsStore(defaults: suite)
        XCTAssertEqual(store.appSettings.rewriteProvider, .local(modelID: .gemma4_e4b_it_mxfp8))
        XCTAssertEqual(store.appSettings.selectedLocalModel, .gemma4_e4b_it_mxfp8)
    }
}
