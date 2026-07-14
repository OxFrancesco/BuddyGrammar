package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Test

class HandwritingTextFormatterTest {

    @Test
    fun `lowercases all caps recognition inside a sentence`() {
        assertEquals(
            "hello world",
            HandwritingTextFormatter.textForInsertion("HELLO WORLD", "I wrote "),
        )
    }

    @Test
    fun `uses sentence case at sentence start`() {
        assertEquals(
            "Hello world",
            HandwritingTextFormatter.textForInsertion("HELLO WORLD", "Previous sentence. "),
        )
        assertEquals(
            "Hello",
            HandwritingTextFormatter.textForInsertion("hello", ""),
        )
    }

    @Test
    fun `lowercases title case word inside a sentence`() {
        assertEquals(
            "hello world",
            HandwritingTextFormatter.textForInsertion("Hello world", "I wrote "),
        )
        assertEquals(
            "the",
            HandwritingTextFormatter.textForInsertion("The", "jumped over "),
        )
    }

    @Test
    fun `keeps acronyms mixed case and pronoun I`() {
        assertEquals(
            "NASA launch",
            HandwritingTextFormatter.textForInsertion("NASA launch", "about the "),
        )
        assertEquals(
            "BuddyGrammar iOS",
            HandwritingTextFormatter.textForInsertion("BuddyGrammar iOS", "Using "),
        )
        assertEquals(
            "I'm here",
            HandwritingTextFormatter.textForInsertion("I'm here", "then "),
        )
        assertEquals(
            "I",
            HandwritingTextFormatter.textForInsertion("I", "and "),
        )
    }

    @Test
    fun `restores standalone i`() {
        assertEquals(
            "when I arrive",
            HandwritingTextFormatter.textForInsertion("when i arrive", "text me "),
        )
    }
}
