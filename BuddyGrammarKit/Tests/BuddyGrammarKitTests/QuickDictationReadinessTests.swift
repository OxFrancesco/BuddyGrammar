import Foundation
import Testing
@testable import BuddyGrammarKit

@Suite("Dynamic Island dictation readiness")
struct QuickDictationReadinessTests {
    @Test("A five-minute window expires exactly five minutes after activation")
    func fiveMinuteExpiry() {
        let startedAt = Date(timeIntervalSince1970: 1_000)

        #expect(
            QuickDictationDuration.fiveMinutes.expirationDate(startedAt: startedAt)
                == Date(timeIntervalSince1970: 1_300)
        )
    }

    @Test("Existing installs default to a disabled five-minute readiness window")
    func legacySettingsMigration() throws {
        let settings = try JSONDecoder().decode(
            BuddyGrammarSettings.self,
            from: Data("{}".utf8)
        )

        #expect(settings.enablesQuickDictation == false)
        #expect(settings.quickDictationDuration == .fiveMinutes)
        #expect(settings.quickDictationExpiresAt == nil)
    }

    @Test("Long and unlimited readiness windows match the product choices")
    func longAndUnlimitedWindows() {
        let startedAt = Date(timeIntervalSince1970: 1_000)

        #expect(
            QuickDictationDuration.twelveHours.expirationDate(startedAt: startedAt)
                == Date(timeIntervalSince1970: 44_200)
        )
        #expect(QuickDictationDuration.always.expirationDate(startedAt: startedAt) == nil)
    }

    @Test("Readiness choice and expiry survive App Group persistence")
    func settingsRoundTrip() throws {
        let expiry = Date(timeIntervalSince1970: 44_200)
        let original = BuddyGrammarSettings(
            enablesQuickDictation: true,
            quickDictationDuration: .twelveHours,
            quickDictationExpiresAt: expiry
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BuddyGrammarSettings.self, from: data)

        #expect(decoded.enablesQuickDictation)
        #expect(decoded.quickDictationDuration == .twelveHours)
        #expect(decoded.quickDictationExpiresAt == expiry)
    }
}
