package com.francescooddo.buddygrammar.core.adaptive

import org.junit.Assert.assertEquals
import org.junit.Test

class TypingProfileCodecTest {
    @Test
    fun `persistence contains aggregate fields only and round trips`() {
        val profile = TypingProfileSnapshot(
            observationCount = 12,
            meanOffsetX = 0.25,
            meanOffsetY = -0.125,
            keyOffsets = mapOf(
                "e" to KeyOffsetAggregate(
                    observationCount = 8,
                    meanOffsetX = 0.2,
                    meanOffsetY = -0.1,
                ),
            ),
        )

        val encoded = TypingProfileCodec.encode(profile)

        assertEquals("2|12|0.25|-0.125|e,8,0.2,-0.1", encoded)
        assertEquals(profile, TypingProfileCodec.decode(encoded))
    }

    @Test
    fun `version one global profile migrates without losing its safe aggregate`() {
        val migrated = TypingProfileCodec.decode("1|20|0.3|-0.1")

        assertEquals(TypingProfileSnapshot.CURRENT_PROFILE_VERSION, migrated.version)
        assertEquals(20, migrated.observationCount)
        assertEquals(0.3, migrated.meanOffsetX, 0.0)
        assertEquals(-0.1, migrated.meanOffsetY, 0.0)
        assertEquals(emptyMap<String, KeyOffsetAggregate>(), migrated.keyOffsets)
    }

    @Test
    fun `invalid persisted data falls back to an empty profile`() {
        assertEquals(TypingProfileSnapshot(), TypingProfileCodec.decode("not-a-profile"))
    }
}
