@testable import BuddyGrammar
import XCTest

@MainActor
final class MenuBarStatusModelTests: XCTestCase {
    func testShowCancelsPendingReset() async {
        let model = MenuBarStatusModel()

        model.show(.success(message: "Copied to clipboard"))
        model.reset(after: .milliseconds(30))
        model.show(.sending(profileName: "Grammar"))

        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(model.phase, .sending(profileName: "Grammar"))
    }

    func testResetReturnsToIdleAfterDelay() async {
        let model = MenuBarStatusModel()

        model.show(.failure(message: "Missing API key"))
        model.reset(after: .milliseconds(20))

        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(model.phase, .idle)
    }
}
