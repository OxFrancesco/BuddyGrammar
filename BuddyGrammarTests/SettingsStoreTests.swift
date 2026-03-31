@testable import BuddyGrammar
import XCTest

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultGrammarProfileIsPresent() {
        let suite = UserDefaults(suiteName: #function)!
        suite.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: suite)

        XCTAssertEqual(store.profiles.first?.id, PromptProfile.grammarProfileID)
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
}
