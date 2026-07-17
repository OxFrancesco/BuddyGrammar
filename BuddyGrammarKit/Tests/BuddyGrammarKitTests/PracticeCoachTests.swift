import BuddyGrammarKit
import XCTest

final class PracticeCoachTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testFreshCoachSelectsTheSameCuratedMotorPromptDeterministically() {
        let firstCoach = PracticeCoach()
        let secondCoach = PracticeCoach()
        let request = PracticeRequest(track: .motor)

        let first = firstCoach.nextPrompt(request: request, now: now)
        let second = secondCoach.nextPrompt(request: request, now: now)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.track, .motor)
        XCTAssertFalse(first.expectedText.isEmpty)
        XCTAssertEqual(first.motorTarget, first.expectedText)
        XCTAssertFalse(first.isHoldout)
    }

    func testRecordingSeparatesRawAndDecodedAccuracyAndLearnsAlignedKeys() throws {
        var coach = PracticeCoach()
        let prompt = PracticePrompt(
            id: "test-home",
            kind: .copy,
            track: .motor,
            instruction: "Type home.",
            stimulus: "home",
            expectedText: "home",
            motorTarget: "home",
            skillIDs: []
        )

        let result = coach.record(
            attempt: PracticeAttempt(
                prompt: prompt,
                rawText: "homr",
                decodedText: "home"
            ),
            now: now
        )

        XCTAssertEqual(result.status, .recorded)
        XCTAssertEqual(result.rawAccuracy, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(result.decodedAccuracy, 1, accuracy: 0.000_001)
        XCTAssertEqual(coach.snapshot.meanRawAccuracy, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(coach.snapshot.meanDecodedAccuracy, 1, accuracy: 0.000_001)

        let correctKey = try XCTUnwrap(coach.snapshot.skills["motor:key:h"])
        let missedKey = try XCTUnwrap(coach.snapshot.skills["motor:key:e"])
        XCTAssertGreaterThan(correctKey.mastery, missedKey.mastery)
        XCTAssertGreaterThan(missedKey.weightedFailures, 0)
        XCTAssertTrue(result.updatedSkillIDs.contains("motor:transition:me"))
    }

    func testEvidenceWeightsUnaidedRecallAboveStructuredAndAssistedCopying() throws {
        let skillID = "writing:tense:simple-past"
        let expectedText = "I finished the report."
        let freePrompt = writingPrompt(
            id: "free",
            kind: .freeProduction,
            expectedText: expectedText,
            skillID: skillID
        )
        let correctionPrompt = writingPrompt(
            id: "correction",
            kind: .correction,
            expectedText: expectedText,
            skillID: skillID
        )
        let copyPrompt = writingPrompt(
            id: "copy",
            kind: .copy,
            expectedText: expectedText,
            skillID: skillID
        )
        var freeCoach = PracticeCoach()
        var correctionCoach = PracticeCoach()
        var copyCoach = PracticeCoach()

        freeCoach.record(
            attempt: PracticeAttempt(prompt: freePrompt, rawText: expectedText),
            now: now
        )
        correctionCoach.record(
            attempt: PracticeAttempt(prompt: correctionPrompt, rawText: expectedText),
            now: now
        )
        copyCoach.record(
            attempt: PracticeAttempt(
                prompt: copyPrompt,
                rawText: expectedText,
                assistance: .copied
            ),
            now: now
        )

        let freeEvidence = try XCTUnwrap(freeCoach.snapshot.skills[skillID])
        let correctionEvidence = try XCTUnwrap(correctionCoach.snapshot.skills[skillID])
        let copiedEvidence = try XCTUnwrap(copyCoach.snapshot.skills[skillID])
        XCTAssertGreaterThan(
            freeEvidence.weightedSuccesses,
            correctionEvidence.weightedSuccesses
        )
        XCTAssertGreaterThan(
            correctionEvidence.weightedSuccesses,
            copiedEvidence.weightedSuccesses
        )
    }

    func testDelayedRecallCarriesMoreEvidenceThanImmediateRecall() {
        let prompt = writingPrompt(
            id: "delayed",
            kind: .freeProduction,
            expectedText: "I went home.",
            skillID: "writing:tense:irregular-past"
        )
        var coach = PracticeCoach()

        let immediate = coach.record(
            attempt: PracticeAttempt(prompt: prompt, rawText: prompt.expectedText),
            now: now
        )
        let delayed = coach.record(
            attempt: PracticeAttempt(prompt: prompt, rawText: prompt.expectedText),
            now: now.addingTimeInterval(7 * 86_400)
        )

        XCTAssertGreaterThan(delayed.evidenceWeight, immediate.evidenceWeight)
    }

    func testAbandonmentRecordsExposureWithoutCreatingFailureEvidence() {
        let prompt = writingPrompt(
            id: "abandoned",
            kind: .correction,
            expectedText: "She goes home.",
            skillID: "writing:agreement:third-person"
        )
        var coach = PracticeCoach()

        let result = coach.record(
            attempt: PracticeAttempt(
                prompt: prompt,
                rawText: "",
                abandoned: true
            ),
            now: now
        )

        XCTAssertEqual(result.status, .abandoned)
        XCTAssertEqual(result.updatedSkillIDs, [])
        XCTAssertEqual(coach.snapshot.completedAttempts, 0)
        XCTAssertEqual(coach.snapshot.abandonedAttempts, 1)
        XCTAssertTrue(coach.snapshot.skills.isEmpty)
        XCTAssertEqual(coach.snapshot.items[prompt.id]?.exposures, 1)
    }

    func testHoldoutAttemptReturnsScoresWithoutChangingProfileOrTrainingSelection() {
        var coach = PracticeCoach()
        let request = PracticeRequest(track: .motor)
        let trainingBefore = coach.nextPrompt(request: request, now: now)
        let holdout = coach.nextPrompt(
            request: PracticeRequest(track: .motor, retentionDay: 7),
            now: now
        )
        let snapshotBefore = coach.snapshot

        let result = coach.record(
            attempt: PracticeAttempt(prompt: holdout, rawText: holdout.expectedText),
            now: now
        )

        XCTAssertTrue(holdout.isHoldout)
        XCTAssertEqual(result.status, .holdout)
        XCTAssertEqual(result.rawAccuracy, 1)
        XCTAssertEqual(result.updatedSkillIDs, [])
        XCTAssertEqual(coach.snapshot, snapshotBefore)
        XCTAssertEqual(coach.nextPrompt(request: request, now: now), trainingBefore)

        let checkpointIDs = [1, 7, 28].map { day in
            coach.nextPrompt(
                request: PracticeRequest(track: .motor, retentionDay: day),
                now: now
            ).id
        }
        XCTAssertEqual(Set(checkpointIDs).count, 3)
    }

    func testEachObservationCreatesOneSevenAndTwentyEightDayCheckpoints() throws {
        let prompt = writingPrompt(
            id: "retention",
            kind: .reconstruction,
            expectedText: "We arrived early.",
            skillID: "writing:tense:simple-past"
        )
        var coach = PracticeCoach()

        coach.record(
            attempt: PracticeAttempt(prompt: prompt, rawText: prompt.expectedText),
            now: now
        )

        let state = try XCTUnwrap(coach.snapshot.skills[prompt.skillIDs[0]])
        XCTAssertEqual(state.retentionSchedule.map(\.day), [1, 7, 28])
        XCTAssertEqual(
            state.retentionSchedule.map(\.dueAt),
            [1, 7, 28].map { now.addingTimeInterval(Double($0) * 86_400) }
        )
        XCTAssertGreaterThan(state.halfLifeDays, 1)
    }

    func testSchedulerRotatesExposedItemsAndTargetsWeakSkillsAndGoals() {
        var motorCoach = PracticeCoach()
        let motorRequest = PracticeRequest(track: .motor)
        let first = motorCoach.nextPrompt(request: motorRequest, now: now)
        motorCoach.record(
            attempt: PracticeAttempt(prompt: first, rawText: first.expectedText),
            now: now
        )
        let second = motorCoach.nextPrompt(request: motorRequest, now: now)
        XCTAssertNotEqual(second.id, first.id)

        var writingCoach = PracticeCoach()
        let failedArticle = writingPrompt(
            id: "external-article-signal",
            kind: .correction,
            expectedText: "an",
            skillID: "writing:articles:a-an"
        )
        writingCoach.record(
            attempt: PracticeAttempt(prompt: failedArticle, rawText: ""),
            now: now
        )
        XCTAssertTrue(
            writingCoach.nextPrompt(
                request: PracticeRequest(track: .writing),
                now: now
            ).skillIDs.contains("writing:articles:a-an")
        )

        let goalPrompt = PracticeCoach().nextPrompt(
            request: PracticeRequest(
                track: .writing,
                goalSkillIDs: ["writing:tense:irregular-past"]
            ),
            now: now
        )
        XCTAssertTrue(goalPrompt.skillIDs.contains("writing:tense:irregular-past"))
    }

    func testMixedAttemptUpdatesSeparateMotorAndWritingFamilies() throws {
        let prompt = PracticePrompt(
            id: "mixed",
            kind: .mixedTransfer,
            track: .mixed,
            instruction: "Write from memory.",
            expectedText: "home",
            motorTarget: "home",
            skillIDs: ["writing:spelling:home"]
        )
        var coach = PracticeCoach()

        coach.record(
            attempt: PracticeAttempt(
                prompt: prompt,
                rawText: "homr",
                decodedText: "home",
                assistance: .adaptiveKeyboard
            ),
            now: now
        )

        XCTAssertEqual(
            try XCTUnwrap(coach.snapshot.skills["motor:key:e"]).family,
            .motor
        )
        XCTAssertEqual(
            try XCTUnwrap(coach.snapshot.skills["writing:spelling:home"]).family,
            .writing
        )
    }

    func testProfileRoundTripContainsAggregatesButNeverPracticeResponses() throws {
        let privateResponse = "PRIVATE-PRACTICE-RESPONSE-9472"
        let prompt = writingPrompt(
            id: "privacy",
            kind: .freeProduction,
            expectedText: "A harmless expected answer.",
            skillID: "writing:privacy-test"
        )
        var coach = PracticeCoach()
        coach.record(
            attempt: PracticeAttempt(
                prompt: prompt,
                rawText: privateResponse,
                decodedText: privateResponse.lowercased()
            ),
            now: now
        )

        let data = try JSONEncoder().encode(coach.snapshot)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(encoded.contains(privateResponse))
        XCTAssertFalse(encoded.contains(privateResponse.lowercased()))
        XCTAssertEqual(
            try JSONDecoder().decode(PracticeProfile.self, from: data),
            coach.snapshot
        )
    }

    func testCuratedBankCanRenderEveryPracticeKind() {
        let coach = PracticeCoach()

        for kind in PracticeKind.allCases {
            let prompt = coach.nextPrompt(
                request: PracticeRequest(track: .mixed, preferredKinds: [kind]),
                now: now
            )
            XCTAssertEqual(prompt.kind, kind)
            XCTAssertFalse(prompt.instruction.isEmpty)
            XCTAssertFalse(prompt.expectedText.isEmpty)
        }
    }

    private func writingPrompt(
        id: String,
        kind: PracticeKind,
        expectedText: String,
        skillID: String
    ) -> PracticePrompt {
        PracticePrompt(
            id: id,
            kind: kind,
            track: .writing,
            instruction: "Complete the writing exercise.",
            expectedText: expectedText,
            skillIDs: [skillID]
        )
    }
}
