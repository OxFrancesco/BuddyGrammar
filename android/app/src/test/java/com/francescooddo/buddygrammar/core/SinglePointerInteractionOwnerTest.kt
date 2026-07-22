package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SinglePointerInteractionOwnerTest {
    @Test
    fun `interleaved second pointer cannot steal or release ownership`() {
        val owner = SinglePointerInteractionOwner<Long>()

        assertTrue(owner.acquire(11L))
        assertFalse(owner.acquire(22L))
        assertEquals(11L, owner.activeToken)
        assertFalse(owner.release(22L))
        assertEquals(11L, owner.activeToken)
        assertTrue(owner.release(11L))

        assertTrue(owner.acquire(22L))
        assertEquals(22L, owner.activeToken)
    }

    @Test
    fun `duplicate down is rejected and lifecycle reset clears ownership`() {
        val owner = SinglePointerInteractionOwner<String>()

        assertTrue(owner.acquire("first"))
        assertFalse(owner.acquire("first"))
        owner.reset()

        assertNull(owner.activeToken)
        assertTrue(owner.acquire("second"))
    }
}
