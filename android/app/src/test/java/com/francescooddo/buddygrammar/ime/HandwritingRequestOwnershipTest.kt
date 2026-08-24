package com.francescooddo.buddygrammar.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HandwritingRequestOwnershipTest {
    @Test
    fun `stroke layer and field changes reject stale local or cloud work`() {
        val ownership = HandwritingRequestOwnership(initialFieldEpoch = 7)
        val first = ownership.begin()
        assertTrue(ownership.isOwner(first))

        ownership.inputChanged()
        assertFalse(ownership.isOwner(first))
        val second = ownership.begin()

        ownership.changeField(8)
        assertFalse(ownership.isOwner(second))
        val third = ownership.begin()
        assertEquals(8, third.fieldEpoch)
        assertTrue(ownership.finish(third))
        assertFalse(ownership.isOwner(third))
    }
}
