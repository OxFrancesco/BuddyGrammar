package com.francescooddo.buddygrammar.ime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CorrectionRequestOwnershipTest {
    @Test
    fun `obsolete completion cannot clear a newer correction request`() {
        val ownership = CorrectionRequestOwnership()
        val first = ownership.begin()
        val second = ownership.begin()

        assertFalse(ownership.finish(first))
        assertTrue(ownership.isOwner(second))
        assertTrue(ownership.finish(second))
        assertFalse(ownership.isOwner(second))
    }

    @Test
    fun `cancellation invalidates the active request before its finally block runs`() {
        val ownership = CorrectionRequestOwnership()
        val request = ownership.begin()

        ownership.cancel()

        assertFalse(ownership.finish(request))
    }

    @Test
    fun `only a changed editor selection invalidates correction state`() {
        assertFalse(CorrectionLifecyclePolicy.selectionInvalidates(4, 4, 4, 4))
        assertTrue(CorrectionLifecyclePolicy.selectionInvalidates(4, 4, 2, 4))
        assertTrue(CorrectionLifecyclePolicy.selectionInvalidates(2, 4, 4, 4))
    }
}
