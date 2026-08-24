import XCTest

@testable import BuddyGrammarKit

final class KeyboardDictationHandoffTests: XCTestCase {
    func testURLOpensDictationWithKeyboardSource() throws {
        let sessionID = UUID()
        let url = try XCTUnwrap(KeyboardDictationHandoff.url(for: sessionID))

        XCTAssertEqual(url.scheme, "buddygrammar")
        XCTAssertEqual(url.host, "dictation")
        XCTAssertTrue(url.absoluteString.contains("source=keyboard"))
    }

    func testSessionIDRoundTrips() throws {
        let sessionID = UUID()
        let url = try XCTUnwrap(KeyboardDictationHandoff.url(for: sessionID))

        XCTAssertEqual(KeyboardDictationHandoff.sessionID(from: url), sessionID)
    }

    func testRejectsForeignURLs() {
        XCTAssertNil(
            KeyboardDictationHandoff.sessionID(from: URL(string: "https://buddygrammar.ai")!)
        )
        XCTAssertNil(
            KeyboardDictationHandoff.sessionID(
                from: URL(string: "buddygrammar://dictation?session=\(UUID().uuidString)")!
            )
        )
        XCTAssertNil(
            KeyboardDictationHandoff.sessionID(
                from: URL(string: "buddygrammar://dictation?source=app")!
            )
        )
        XCTAssertNil(
            KeyboardDictationHandoff.sessionID(
                from: URL(string: "buddygrammar://dictation?source=keyboard&session=not-a-uuid")!
            )
        )
    }
}
