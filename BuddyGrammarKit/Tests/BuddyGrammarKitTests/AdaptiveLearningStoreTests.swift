import XCTest
@testable import BuddyGrammarKit

final class AdaptiveLearningStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AdaptiveLearningStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testProfilesRoundTripInIndependentRecords() throws {
        let store = AdaptiveLearningStore(defaults: defaults)
        let typing = TypingProfile(
            explicitObservationCount: 4,
            keyOffsets: [
                "e": TypingKeyAggregate(sampleCount: 4, meanX: 0.12, meanY: -0.04),
            ]
        )
        let practice = PracticeProfile(
            skills: [
                "motor:key:e": PracticeSkillState(
                    id: "motor:key:e",
                    family: .motor,
                    observations: 3,
                    mastery: 0.8
                ),
            ],
            completedAttempts: 3,
            meanRawAccuracy: 0.75,
            meanDecodedAccuracy: 0.9
        )

        try store.saveTypingProfile(typing)
        try store.savePracticeProfile(practice)

        XCTAssertEqual(store.loadTypingProfile(), typing)
        XCTAssertEqual(store.loadPracticeProfile(), practice)
    }

    func testPracticeSessionExpiresAndIsDeleted() throws {
        let store = AdaptiveLearningStore(defaults: defaults)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let session = ActivePracticeSession(
            promptID: "motor-home",
            expectedText: "home",
            languageCode: "en",
            startedAt: startedAt
        )
        try store.saveActivePracticeSession(session)

        XCTAssertEqual(
            store.loadActivePracticeSession(now: startedAt.addingTimeInterval(60)),
            session
        )
        XCTAssertNil(
            store.loadActivePracticeSession(
                now: startedAt.addingTimeInterval(
                    AdaptiveLearningStore.practiceSessionLifetime + 1
                )
            )
        )
        XCTAssertNil(store.loadActivePracticeSession(now: startedAt))
    }

    func testScopesCanBeResetIndependently() throws {
        let store = AdaptiveLearningStore(defaults: defaults)
        let typing = TypingProfile(explicitObservationCount: 2)
        let practice = PracticeProfile(completedAttempts: 2)
        try store.saveTypingProfile(typing)
        try store.savePracticeProfile(practice)

        store.reset(.typing)

        XCTAssertEqual(store.loadTypingProfile(), TypingProfile())
        XCTAssertEqual(store.loadPracticeProfile(), practice)

        store.reset(.all)

        XCTAssertEqual(store.loadPracticeProfile(), PracticeProfile())
    }
}
