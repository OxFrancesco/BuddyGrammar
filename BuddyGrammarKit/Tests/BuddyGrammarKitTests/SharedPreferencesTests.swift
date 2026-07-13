import XCTest
@testable import BuddyGrammarKit

final class SharedPreferencesTests: XCTestCase {
    func testInstallationIdentifierIsStable() {
        let preferences = SharedPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.installationIdentifier(),
            preferences.installationIdentifier()
        )
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "BuddyGrammarKitTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSettingsRoundTrip() throws {
        let preferences = SharedPreferences(defaults: defaults)
        var settings = BuddyGrammarSettings.default
        settings.openRouterModelID = "test/model"
        settings.hasAcceptedCloudProcessing = true

        try preferences.saveSettings(settings)

        XCTAssertEqual(preferences.loadSettings(), settings)
    }

    func testPendingTranscriptRoundTripAndClear() throws {
        let preferences = SharedPreferences(defaults: defaults)
        let now = Date(timeIntervalSince1970: 123)
        let transcript = PendingTranscript(
            text: "A dictated sentence.",
            createdAt: now
        )

        try preferences.savePendingTranscript(transcript)
        XCTAssertEqual(preferences.loadPendingTranscript(now: now), transcript)

        preferences.clearPendingTranscript()
        XCTAssertNil(preferences.loadPendingTranscript(now: now))
    }

    func testExpiredPendingTranscriptIsDiscarded() throws {
        let preferences = SharedPreferences(defaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 123)
        let transcript = PendingTranscript(text: "Sensitive draft", createdAt: createdAt)

        try preferences.savePendingTranscript(transcript)

        let afterExpiry = createdAt.addingTimeInterval(
            BuddyGrammarConfiguration.pendingTranscriptLifetime + 1
        )
        XCTAssertNil(preferences.loadPendingTranscript(now: afterExpiry))
        XCTAssertNil(preferences.loadPendingTranscript(now: createdAt))
    }
}
