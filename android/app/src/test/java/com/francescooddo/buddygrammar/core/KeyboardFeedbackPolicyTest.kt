package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardFeedbackPolicyTest {
    @Test
    fun `standard click requires key feedback system sounds and normal ringer`() {
        assertTrue(
            KeyboardFeedbackPolicy.shouldPlayStandardClick(
                InteractionFeedback.KEY,
                systemSoundEffectsEnabled = true,
                ringerModeNormal = true,
            ),
        )
        assertFalse(
            KeyboardFeedbackPolicy.shouldPlayStandardClick(
                InteractionFeedback.SELECTION,
                systemSoundEffectsEnabled = true,
                ringerModeNormal = true,
            ),
        )
        assertFalse(
            KeyboardFeedbackPolicy.shouldPlayStandardClick(
                InteractionFeedback.KEY,
                systemSoundEffectsEnabled = false,
                ringerModeNormal = true,
            ),
        )
        assertFalse(
            KeyboardFeedbackPolicy.shouldPlayStandardClick(
                InteractionFeedback.KEY,
                systemSoundEffectsEnabled = true,
                ringerModeNormal = false,
            ),
        )
    }
}
