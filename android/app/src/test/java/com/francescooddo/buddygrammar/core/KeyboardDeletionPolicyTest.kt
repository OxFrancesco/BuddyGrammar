package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class KeyboardDeletionPolicyTest {
    private val policy = KeyboardDeletionPolicy(
        GraphemeBoundaryProvider { text ->
            buildList {
                add(0)
                Regex("\\X").findAll(text).forEach { match -> add(match.range.last + 1) }
            }.distinct().toIntArray()
        },
    )

    @Test
    fun `word delete keeps whitespace and punctuation as conservative runs`() {
        assertEquals(1, policy.utf16UnitsBeforeCursor("hello ", false))
        assertEquals(3, policy.utf16UnitsBeforeCursor("hello   ", false))
        assertEquals(5, policy.utf16UnitsBeforeCursor("say can't", false))
        assertEquals(1, policy.utf16UnitsBeforeCursor("hello!", false))
        assertEquals(1, policy.utf16UnitsBeforeCursor("hello!!!", false))
        assertEquals(11, policy.utf16UnitsBeforeCursor("hello👨‍👩‍👧‍👦", false))
        assertEquals(0, policy.utf16UnitsBeforeCursor("", false))
    }

    @Test
    fun `word delete never separates a combining or emoji grapheme`() {
        assertEquals(5, policy.utf16UnitsBeforeCursor("say cafe\u0301", false))
        assertEquals(4, policy.utf16UnitsBeforeCursor("go 👍🏽", false))
        assertEquals(4, policy.utf16UnitsBeforeCursor("go 🇮🇹", false))
        assertEquals(11, policy.utf16UnitsBeforeCursor("go 👨‍👩‍👧‍👦", false))
    }

    @Test
    fun `word delete rejects a token touching a truncated leading edge`() {
        assertNull(policy.utf16UnitsBeforeCursor("unfinished", true))
        assertEquals(1, policy.utf16UnitsBeforeCursor("unfinished!", true))
    }
}
