package com.francescooddo.buddygrammar.core.adaptive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class AdaptivePracticeStoreTest {
    @Test
    fun `aggregate practice profile round trips without response text`() {
        var payload: String? = null
        val store = AdaptivePracticeStore(
            readPayload = { payload },
            writePayload = { payload = it },
        )
        val profile = PracticeProfile(
            skills = mapOf(
                "motor:key:e" to PracticeSkillState(
                    id = "motor:key:e",
                    family = PracticeSkillFamily.MOTOR,
                    observations = 3,
                    weightedSuccesses = 1.8,
                    weightedFailures = 0.4,
                    mastery = 0.74,
                    uncertainty = 0.42,
                    halfLifeDays = 5.5,
                    lastObservedAtEpochMillis = 1_750_000_000_000L,
                    retentionSchedule = listOf(
                        PracticeRetentionCheckpoint(1, 1_750_086_400_000L),
                    ),
                ),
            ),
            items = mapOf(
                "motor-home" to PracticeItemState(
                    id = "motor-home",
                    exposures = 2,
                    lastPresentedAtEpochMillis = 1_750_000_000_000L,
                ),
            ),
            completedAttempts = 2,
            abandonedAttempts = 1,
            meanRawAccuracy = 0.75,
            meanDecodedAccuracy = 0.9,
        )

        store.save(profile)

        assertEquals(profile, store.load())
        assertNotNull(payload)
        val encoded = requireNotNull(payload)
        assertFalse(encoded.contains("rawText"))
        assertFalse(encoded.contains("decodedText"))
        assertFalse(encoded.contains("expectedText"))
        assertFalse(encoded.contains("stimulus"))
    }

    @Test
    fun `active practice marker contains only curated target context and expires`() {
        var sessionPayload: String? = null
        val store = AdaptivePracticeStore(
            readPayload = { null },
            writePayload = {},
            readSessionPayload = { sessionPayload },
            writeSessionPayload = { sessionPayload = it },
        )
        val session = ActivePracticeSession(
            promptId = "motor-home",
            expectedText = "home",
            startedAtEpochMillis = 1_750_000_000_000L,
            expiresAtEpochMillis = 1_750_001_800_000L,
        )

        store.saveActiveSession(session)

        assertEquals(session, store.loadActiveSession(1_750_000_100_000L))
        assertNotNull(sessionPayload)
        val encoded = requireNotNull(sessionPayload)
        assertFalse(encoded.contains("rawText"))
        assertFalse(encoded.contains("response"))
        assertNull(store.loadActiveSession(1_750_001_800_001L))
        assertNull(sessionPayload)
    }

    @Test
    fun `reset removes both aggregate progress and the active marker`() {
        var profilePayload: String? = null
        var sessionPayload: String? = null
        val store = AdaptivePracticeStore(
            readPayload = { profilePayload },
            writePayload = { profilePayload = it },
            readSessionPayload = { sessionPayload },
            writeSessionPayload = { sessionPayload = it },
        )
        store.save(PracticeProfile(completedAttempts = 4))
        store.saveActiveSession(
            ActivePracticeSession(
                promptId = "writing-article",
                expectedText = "an",
                startedAtEpochMillis = 1_750_000_000_000L,
                expiresAtEpochMillis = 1_750_001_800_000L,
            ),
        )

        store.reset()

        assertEquals(PracticeProfile(), store.load())
        assertNull(store.loadActiveSession(1_750_000_100_000L))
        assertNull(profilePayload)
        assertNull(sessionPayload)
    }
}
