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

    func testTypingResetGenerationRejectsDirtyPreResetProfile() throws {
        let store = AdaptiveLearningStore(defaults: defaults)
        let preferences = SharedPreferences(defaults: defaults)
        let staleGeneration = preferences.loadLearningResetGenerations().typing
        let dirtyProfile = TypingProfile(explicitObservationCount: 9)

        store.reset(.typing)

        let currentGeneration = preferences.loadLearningResetGenerations().typing
        XCTAssertNotEqual(currentGeneration, staleGeneration)
        XCTAssertFalse(
            try store.saveTypingProfile(
                dirtyProfile,
                expectedResetGeneration: staleGeneration
            )
        )
        XCTAssertEqual(store.loadTypingProfile(), TypingProfile())
        XCTAssertTrue(
            try store.saveTypingProfile(
                dirtyProfile,
                expectedResetGeneration: currentGeneration
            )
        )
        XCTAssertEqual(store.loadTypingProfile(), dirtyProfile)
    }

    func testTypingAndLanguageResetGenerationsRemainIndependent() {
        let store = AdaptiveLearningStore(defaults: defaults)
        let preferences = SharedPreferences(defaults: defaults)

        preferences.resetPersonalLanguageLearning()
        XCTAssertEqual(
            preferences.loadLearningResetGenerations(),
            LearningResetGenerations(language: 1, typing: 0)
        )

        store.reset(.typing)
        XCTAssertEqual(
            preferences.loadLearningResetGenerations(),
            LearningResetGenerations(language: 1, typing: 1)
        )
    }

    func testGenerationZeroLoadsLegacyUnwrappedTypingProfile() throws {
        let legacyProfile = TypingProfile(explicitObservationCount: 3)
        defaults.set(
            try JSONEncoder().encode(legacyProfile),
            forKey: "BuddyGrammar.adaptive.typing.v1"
        )

        XCTAssertEqual(
            AdaptiveLearningStore(defaults: defaults).loadTypingProfile(),
            legacyProfile
        )
    }
}
