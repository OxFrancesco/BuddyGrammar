package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CorrectionCandidatePreferenceTest {
    @Test
    fun `correction action target retains the exact typed suggestion pair and language`() {
        val correction = Suggestion(
            text = "the",
            replaceBeforeCursor = 3,
            appendSpace = true,
            kind = SuggestionKind.CORRECTION,
        )

        assertEquals(
            CorrectionCandidatePreference("teh", "the", "en-US"),
            CorrectionCandidatePreferences.target(correction, "Please type teh", "en-US"),
        )
    }

    @Test
    fun `non correction and stale editor context expose no preference action`() {
        val completion = Suggestion("there", 3, true, SuggestionKind.COMPLETION)
        val correction = Suggestion("the", 30, true, SuggestionKind.CORRECTION)

        assertNull(CorrectionCandidatePreferences.target(completion, "the", "en-US"))
        assertNull(CorrectionCandidatePreferences.target(correction, "short", "en-US"))
    }
}
