import Foundation
import Testing
@testable import BuddyGrammarKit

struct KeyboardDictationHandoffTests {
    @Test
    func handoffURLRoundTripsItsSessionIdentifier() throws {
        let sessionID = UUID(uuidString: "6E7DB394-999E-47D1-A8A5-565A74BD6D38")!

        let url = KeyboardDictationHandoff.url(for: sessionID)

        #expect(url?.absoluteString == "buddygrammar://dictation?source=keyboard&session=6E7DB394-999E-47D1-A8A5-565A74BD6D38")
        #expect(KeyboardDictationHandoff.sessionID(from: try #require(url)) == sessionID)
    }

    @Test
    func handoffRejectsUnrelatedOrMalformedURLs() {
        #expect(
            KeyboardDictationHandoff.sessionID(
                from: URL(string: "other://dictation?session=6E7DB394-999E-47D1-A8A5-565A74BD6D38")!
            ) == nil
        )
        #expect(
            KeyboardDictationHandoff.sessionID(
                from: URL(string: "buddygrammar://settings?session=6E7DB394-999E-47D1-A8A5-565A74BD6D38")!
            ) == nil
        )
        #expect(
            KeyboardDictationHandoff.sessionID(
                from: URL(string: "buddygrammar://dictation?session=not-a-uuid")!
            ) == nil
        )
    }
}
