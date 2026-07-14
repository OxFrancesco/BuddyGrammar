package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PendingTranscriptTest {
    @Test
    fun `restores optional language while legacy records remain valid`() {
        assertEquals(
            PendingTranscript("Ciao", 42L, "ita"),
            restorePendingTranscript("  Ciao  ", 42L, " ita "),
        )
        assertEquals(
            PendingTranscript("Legacy", 42L, null),
            restorePendingTranscript("Legacy", 42L, null),
        )
        assertNull(restorePendingTranscript("  ", 42L, "ita"))
        assertNull(restorePendingTranscript("Ciao", 0L, "ita"))
    }

    @Test
    fun `detected transcript language selects the matching personal model scope`() {
        val transcript = restorePendingTranscript("Ciao mondo", 42L, "ita")!!
        val model = PersonalLanguageModel()

        model.learnCommittedText(transcript.text, languageTag = transcript.languageCode!!)

        assertEquals(1, model.usageCount("mondo", "it-IT"))
        assertEquals(0, model.usageCount("mondo", "en-US"))
    }
}
