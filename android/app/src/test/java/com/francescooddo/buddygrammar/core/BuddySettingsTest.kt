package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BuddySettingsTest {
    @Test
    fun `default correction instruction matches the concise cross-platform prompt`() {
        val instruction = BuddySettings().correctionInstruction

        assertTrue(instruction.startsWith("Fix clear grammar"))
        assertTrue(instruction.contains("Leave ambiguous wording unchanged"))
        assertFalse(instruction.contains("Act as a precise copy editor"))
    }

    @Test
    fun `local word correction is enabled by default and can be disabled`() {
        assertTrue(BuddySettings().automaticallyCorrectWords)
        assertFalse(BuddySettings().copy(automaticallyCorrectWords = false).automaticallyCorrectWords)
    }

    @Test
    fun `adaptive keyboard and personalized practice default on and can be disabled`() {
        assertTrue(BuddySettings().adaptiveTypingEnabled)
        assertTrue(BuddySettings().personalizedPracticeEnabled)
        assertFalse(BuddySettings().copy(adaptiveTypingEnabled = false).adaptiveTypingEnabled)
        assertFalse(
            BuddySettings().copy(personalizedPracticeEnabled = false).personalizedPracticeEnabled,
        )
    }

    @Test
    fun `completed dictation is not copied automatically unless the user opts in`() {
        assertFalse(BuddySettings().copiesCompletedDictationToClipboard)
        assertTrue(
            BuddySettings()
                .copy(copiesCompletedDictationToClipboard = true)
                .copiesCompletedDictationToClipboard,
        )
    }

    @Test
    fun `managed models update automatically while custom models remain pinned`() {
        assertEquals(AppConfig.DEFAULT_MODEL, BuddySettings().activeModelId)
        assertEquals(
            "custom/model",
            BuddySettings(
                modelId = " custom/model ",
                usesAutomaticModelUpdates = false,
            ).normalized().activeModelId,
        )
    }

    @Test
    fun `star undo duration is clamped to the supported range`() {
        assertEquals(1, BuddySettings(correctionUndoDurationSeconds = -5).normalized().correctionUndoDurationSeconds)
        assertEquals(10, BuddySettings(correctionUndoDurationSeconds = 50).normalized().correctionUndoDurationSeconds)
    }
}
