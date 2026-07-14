package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BuddySettingsTest {
    @Test
    fun `local word correction is enabled by default and can be disabled`() {
        assertTrue(BuddySettings().automaticallyCorrectWords)
        assertFalse(BuddySettings().copy(automaticallyCorrectWords = false).automaticallyCorrectWords)
    }
}
