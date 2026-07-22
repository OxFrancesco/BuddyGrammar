package com.francescooddo.buddygrammar.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class CorrectionCaptureTargetPolicyTest {
    @Test
    fun `known selection with unavailable text fails closed instead of capturing sentence`() {
        assertEquals(
            CorrectionCaptureTarget.UNAVAILABLE,
            CorrectionCaptureTargetPolicy.target(
                selectionStart = 5,
                selectionEnd = 12,
                hasSelectedCandidate = false,
            ),
        )
        assertEquals(
            CorrectionCaptureTarget.CURRENT_SENTENCE,
            CorrectionCaptureTargetPolicy.target(
                selectionStart = 12,
                selectionEnd = 12,
                hasSelectedCandidate = false,
            ),
        )
        assertEquals(
            CorrectionCaptureTarget.SELECTION,
            CorrectionCaptureTargetPolicy.target(
                selectionStart = 5,
                selectionEnd = 12,
                hasSelectedCandidate = true,
            ),
        )
    }
}
