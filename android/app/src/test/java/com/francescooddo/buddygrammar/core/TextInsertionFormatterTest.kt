package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Test

class TextInsertionFormatterTest {
    @Test
    fun `unknown editor context inserts recognized text literally`() {
        assertEquals(
            TextInsertionFormatter.InsertionPlan(text = "world", deleteBeforeCursor = 0),
            TextInsertionFormatter.planInsertion("world", null),
        )
        assertEquals(
            TextInsertionFormatter.InsertionPlan(text = ", thanks", deleteBeforeCursor = 0),
            TextInsertionFormatter.planInsertion(", thanks", null),
        )
    }

    @Test
    fun `adds a word separator only where sentence context needs one`() {
        assertEquals(" world", TextInsertionFormatter.textForInsertion("world", "Hello"))
        assertEquals("world", TextInsertionFormatter.textForInsertion("world", "Hello "))
        assertEquals("world", TextInsertionFormatter.textForInsertion("world", "("))
        assertEquals(", thanks", TextInsertionFormatter.textForInsertion(", thanks", "Hello"))
    }

    @Test
    fun `removes spaces before closing punctuation only`() {
        assertEquals(2, TextInsertionFormatter.whitespaceToDeleteBefore("Hello  ", ","))
        assertEquals(0, TextInsertionFormatter.whitespaceToDeleteBefore("Hello ", "a"))
        assertEquals(0, TextInsertionFormatter.whitespaceToDeleteBefore("Hello", "."))
    }

    @Test
    fun `plans recognized closing punctuation without a preceding space`() {
        val plan = TextInsertionFormatter.planInsertion(", thanks", "Hello \t")

        assertEquals(2, plan.deleteBeforeCursor)
        assertEquals(", thanks", plan.text)
    }
}
