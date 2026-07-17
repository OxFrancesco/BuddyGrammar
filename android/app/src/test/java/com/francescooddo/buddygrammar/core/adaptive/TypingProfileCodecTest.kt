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
        )

        val encoded = TypingProfileCodec.encode(profile)

        assertEquals("1|12|0.25|-0.125", encoded)
        assertEquals(profile, TypingProfileCodec.decode(encoded))
    }

    @Test
    fun `invalid persisted data falls back to an empty profile`() {
        assertEquals(TypingProfileSnapshot(), TypingProfileCodec.decode("not-a-profile"))
    }
}
