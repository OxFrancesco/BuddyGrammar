package com.francescooddo.buddygrammar.core.adaptive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PracticeCoachTest {
    private val now = 1_750_000_000_000L

    @Test
    fun `fresh coaches select the same curated motor prompt deterministically`() {
        val request = PracticeRequest(track = PracticeTrack.MOTOR)

        val first = PracticeCoach().nextPrompt(request, now)
        val second = PracticeCoach().nextPrompt(request, now)

        assertEquals(first, second)
        assertEquals(PracticeTrack.MOTOR, first.track)
        assertFalse(first.expectedText.isEmpty())
        assertEquals(first.expectedText, first.motorTarget)
        assertFalse(first.isHoldout)
    }

    @Test
    fun `recording separates raw and decoded accuracy and learns aligned keys`() {
        val coach = PracticeCoach()
        val prompt = PracticePrompt(
            id = "test-home",
            kind = PracticeKind.COPY,
            track = PracticeTrack.MOTOR,
            instruction = "Type home.",
            stimulus = "home",
            expectedText = "home",
            motorTarget = "home",
            skillIds = emptySet(),
        )

        val result = coach.record(
            PracticeAttempt(
                prompt = prompt,
                rawText = "homr",
                decodedText = "home",
            ),
            now,
        )

        assertEquals(PracticeRecordStatus.RECORDED, result.status)
        assertEquals(0.75, result.rawAccuracy, 0.000_001)
        assertEquals(1.0, result.decodedAccuracy, 0.000_001)
        assertEquals(0.75, coach.snapshot().meanRawAccuracy, 0.000_001)
        assertEquals(1.0, coach.snapshot().meanDecodedAccuracy, 0.000_001)

        val correctKey = coach.snapshot().skills["motor:key:h"]
        val missedKey = coach.snapshot().skills["motor:key:e"]
        assertNotNull(correctKey)
        assertNotNull(missedKey)
        assertTrue(correctKey!!.mastery > missedKey!!.mastery)
        assertTrue(missedKey.weightedFailures > 0.0)
        assertTrue("motor:transition:me" in result.updatedSkillIds)
    }

    @Test
    fun `unaided recall has stronger evidence than structured and copied practice`() {
        val skillId = "writing:tense:simple-past"
        val expected = "I finished the report."
        val freeCoach = PracticeCoach()
        val correctionCoach = PracticeCoach()
        val copiedCoach = PracticeCoach()

        freeCoach.record(
            PracticeAttempt(
                prompt = writingPrompt("free", PracticeKind.FREE_PRODUCTION, expected, skillId),
                rawText = expected,
            ),
            now,
        )
        correctionCoach.record(
            PracticeAttempt(
                prompt = writingPrompt("correction", PracticeKind.CORRECTION, expected, skillId),
                rawText = expected,
            ),
            now,
        )
        copiedCoach.record(
            PracticeAttempt(
                prompt = writingPrompt("copy", PracticeKind.COPY, expected, skillId),
                rawText = expected,
                assistance = PracticeAssistance.COPIED,
            ),
            now,
        )

        val freeEvidence = freeCoach.snapshot().skills.getValue(skillId).weightedSuccesses
        val correctionEvidence = correctionCoach.snapshot().skills.getValue(skillId).weightedSuccesses
        val copiedEvidence = copiedCoach.snapshot().skills.getValue(skillId).weightedSuccesses
        assertTrue(freeEvidence > correctionEvidence)
        assertTrue(correctionEvidence > copiedEvidence)
    }

    @Test
    fun `assistance ladder discounts evidence in a stable order`() {
        val prompt = writingPrompt(
            id = "assistance",
            kind = PracticeKind.FREE_PRODUCTION,
            expectedText = "I went home.",
            skillId = "writing:assistance",
        )
        val weights = PracticeAssistance.entries.associateWith { assistance ->
            PracticeCoach().record(
                PracticeAttempt(
                    prompt = prompt,
                    rawText = prompt.expectedText,
                    assistance = assistance,
                ),
                now,
            ).evidenceWeight
        }

        assertTrue(weights.getValue(PracticeAssistance.NONE) > weights.getValue(PracticeAssistance.ADAPTIVE_KEYBOARD))
        assertTrue(weights.getValue(PracticeAssistance.ADAPTIVE_KEYBOARD) > weights.getValue(PracticeAssistance.SUGGESTION))
        assertTrue(weights.getValue(PracticeAssistance.SUGGESTION) > weights.getValue(PracticeAssistance.CORRECTION))
        assertTrue(weights.getValue(PracticeAssistance.CORRECTION) > weights.getValue(PracticeAssistance.COPIED))
    }

    @Test
    fun `delayed recall has stronger evidence and schedules retention checkpoints`() {
        val skillId = "writing:tense:irregular-past"
        val prompt = writingPrompt(
            id = "delayed",
            kind = PracticeKind.FREE_PRODUCTION,
            expectedText = "I went home.",
            skillId = skillId,
        )
        val coach = PracticeCoach()

        val immediate = coach.record(PracticeAttempt(prompt, prompt.expectedText), now)
        val delayed = coach.record(
            PracticeAttempt(prompt, prompt.expectedText),
            now + 7 * DAY_MILLIS,
        )

        assertTrue(delayed.evidenceWeight > immediate.evidenceWeight)
        val skill = coach.snapshot().skills.getValue(skillId)
        assertEquals(listOf(1, 7, 28), skill.retentionSchedule.map { it.day })
        assertEquals(
            listOf(1L, 7L, 28L).map { now + 7 * DAY_MILLIS + it * DAY_MILLIS },
            skill.retentionSchedule.map { it.dueAtEpochMillis },
        )
        assertTrue(skill.halfLifeDays > 1.0)
    }

    @Test
    fun `abandonment records exposure without creating failure evidence`() {
        val prompt = writingPrompt(
            id = "abandoned",
            kind = PracticeKind.CORRECTION,
            expectedText = "She goes home.",
            skillId = "writing:agreement:third-person",
        )
        val coach = PracticeCoach()

        val result = coach.record(
            PracticeAttempt(prompt = prompt, rawText = "", abandoned = true),
            now,
        )

        assertEquals(PracticeRecordStatus.ABANDONED, result.status)
        assertTrue(result.updatedSkillIds.isEmpty())
        assertEquals(0, coach.snapshot().completedAttempts)
        assertEquals(1, coach.snapshot().abandonedAttempts)
        assertTrue(coach.snapshot().skills.isEmpty())
        assertEquals(1, coach.snapshot().items[prompt.id]?.exposures)
    }

    @Test
    fun `holdout attempts score without training and checkpoints use distinct items`() {
        val coach = PracticeCoach()
        val trainingRequest = PracticeRequest(track = PracticeTrack.MOTOR)
        val trainingBefore = coach.nextPrompt(trainingRequest, now)
        val holdout = coach.nextPrompt(
            PracticeRequest(track = PracticeTrack.MOTOR, retentionDay = 7),
            now,
        )
        val snapshotBefore = coach.snapshot()

        val result = coach.record(PracticeAttempt(holdout, holdout.expectedText), now)

        assertTrue(holdout.isHoldout)
        assertEquals(PracticeRecordStatus.HOLDOUT, result.status)
        assertEquals(1.0, result.rawAccuracy, 0.0)
        assertTrue(result.updatedSkillIds.isEmpty())
        assertEquals(snapshotBefore, coach.snapshot())
        assertEquals(trainingBefore, coach.nextPrompt(trainingRequest, now))

        val checkpointIds = listOf(1, 7, 28).map { day ->
            coach.nextPrompt(
                PracticeRequest(track = PracticeTrack.MOTOR, retentionDay = day),
                now,
            ).id
        }
        assertEquals(3, checkpointIds.toSet().size)
        assertNotEquals(checkpointIds[0], checkpointIds[1])
    }

    @Test
    fun `scheduler rotates coverage and targets weak forgotten and goal skills`() {
        val motorCoach = PracticeCoach()
        val motorRequest = PracticeRequest(track = PracticeTrack.MOTOR)
        val first = motorCoach.nextPrompt(motorRequest, now)
        motorCoach.record(PracticeAttempt(first, first.expectedText), now)
        val second = motorCoach.nextPrompt(motorRequest, now)
        assertNotEquals(first.id, second.id)

        val weakCoach = PracticeCoach()
        val failedArticle = writingPrompt(
            id = "external-article-signal",
            kind = PracticeKind.CORRECTION,
            expectedText = "an",
            skillId = "writing:articles:a-an",
        )
        weakCoach.record(PracticeAttempt(failedArticle, ""), now)
        assertTrue(
            "writing:articles:a-an" in weakCoach.nextPrompt(
                PracticeRequest(track = PracticeTrack.WRITING),
                now,
            ).skillIds,
        )

        val goal = PracticeCoach().nextPrompt(
            PracticeRequest(
                track = PracticeTrack.WRITING,
                goalSkillIds = setOf("writing:tense:irregular-past"),
            ),
            now,
        )
        assertTrue("writing:tense:irregular-past" in goal.skillIds)

        val forgottenProfile = PracticeProfile(
            skills = mapOf(
                "writing:tense:irregular-past" to PracticeSkillState(
                    id = "writing:tense:irregular-past",
                    family = PracticeSkillFamily.WRITING,
                    observations = 5,
                    weightedSuccesses = 4.0,
                    mastery = 0.9,
                    uncertainty = 0.5,
                    halfLifeDays = 1.0,
                    lastObservedAtEpochMillis = now - 28 * DAY_MILLIS,
                ),
            ),
        )
        val forgotten = PracticeCoach(forgottenProfile).nextPrompt(
            PracticeRequest(track = PracticeTrack.WRITING),
            now,
        )
        assertTrue("writing:tense:irregular-past" in forgotten.skillIds)

        val uncertaintyProfile = PracticeProfile(
            skills = mapOf(
                "writing:articles:a-an" to observedWritingSkill("writing:articles:a-an", 0.1),
                "writing:agreement:third-person" to observedWritingSkill(
                    "writing:agreement:third-person",
                    1.0,
                ),
                "writing:tense:simple-past" to observedWritingSkill("writing:tense:simple-past", 0.1),
                "writing:tense:irregular-past" to observedWritingSkill("writing:tense:irregular-past", 0.1),
            ),
        )
        val uncertain = PracticeCoach(uncertaintyProfile).nextPrompt(
            PracticeRequest(track = PracticeTrack.WRITING),
            now,
        )
        assertTrue("writing:agreement:third-person" in uncertain.skillIds)
    }

    @Test
    fun `curated bank supports every practice ladder kind`() {
        val coach = PracticeCoach()

        PracticeKind.entries.forEach { kind ->
            val prompt = coach.nextPrompt(
                PracticeRequest(
                    track = PracticeTrack.MIXED,
                    preferredKinds = setOf(kind),
                ),
                now,
            )
            assertEquals(kind, prompt.kind)
            assertTrue(prompt.instruction.isNotEmpty())
            assertTrue(prompt.expectedText.isNotEmpty())
        }
    }

    @Test
    fun `mixed attempts update distinct motor and writing skill families`() {
        val prompt = PracticePrompt(
            id = "mixed",
            kind = PracticeKind.MIXED_TRANSFER,
            track = PracticeTrack.MIXED,
            instruction = "Write from memory.",
            expectedText = "home",
            motorTarget = "home",
            skillIds = setOf("writing:spelling:home"),
        )
        val coach = PracticeCoach()

        coach.record(
            PracticeAttempt(
                prompt = prompt,
                rawText = "homr",
                decodedText = "home",
                assistance = PracticeAssistance.ADAPTIVE_KEYBOARD,
            ),
            now,
        )

        assertEquals(
            PracticeSkillFamily.MOTOR,
            coach.snapshot().skills.getValue("motor:key:e").family,
        )
        assertEquals(
            PracticeSkillFamily.WRITING,
            coach.snapshot().skills.getValue("writing:spelling:home").family,
        )
    }

    @Test
    fun `profile snapshot stores aggregates but never practice responses`() {
        val privateResponse = "PRIVATE-PRACTICE-RESPONSE-9472"
        val prompt = writingPrompt(
            id = "privacy",
            kind = PracticeKind.FREE_PRODUCTION,
            expectedText = "A harmless expected answer.",
            skillId = "writing:privacy-test",
        )
        val coach = PracticeCoach()

        coach.record(
            PracticeAttempt(
                prompt = prompt,
                rawText = privateResponse,
                decodedText = privateResponse.lowercase(),
            ),
            now,
        )

        val persistedShape = coach.snapshot().toString()
        assertFalse(persistedShape.contains(privateResponse))
        assertFalse(persistedShape.contains(privateResponse.lowercase()))
        assertEquals(1, coach.snapshot().completedAttempts)
    }

    private fun writingPrompt(
        id: String,
        kind: PracticeKind,
        expectedText: String,
        skillId: String,
    ) = PracticePrompt(
        id = id,
        kind = kind,
        track = PracticeTrack.WRITING,
        instruction = "Complete the writing exercise.",
        expectedText = expectedText,
        skillIds = setOf(skillId),
    )

    private fun observedWritingSkill(id: String, uncertainty: Double) = PracticeSkillState(
        id = id,
        family = PracticeSkillFamily.WRITING,
        observations = 2,
        weightedSuccesses = 1.0,
        weightedFailures = 1.0,
        mastery = 0.5,
        uncertainty = uncertainty,
        halfLifeDays = 1.0,
        lastObservedAtEpochMillis = now,
    )

    private companion object {
        const val DAY_MILLIS = 86_400_000L
    }
}
