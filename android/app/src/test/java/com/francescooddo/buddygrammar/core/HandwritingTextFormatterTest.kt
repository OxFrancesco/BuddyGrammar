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

    @Test
    fun `applies the standalone I rule only in English`() {
        assertEquals(
            "I arrive",
            HandwritingTextFormatter.textForInsertion("i arrive", "then ", "en-US"),
        )
        assertEquals(
            "I libri",
            HandwritingTextFormatter.textForInsertion("I libri", "vedo ", "it-IT"),
        )
        assertEquals(
            "i libri",
            HandwritingTextFormatter.textForInsertion("i libri", "vedo ", "it-IT"),
        )
    }

    @Test
    fun `preserves German noun and all caps recognition casing`() {
        assertEquals(
            "Haus",
            HandwritingTextFormatter.textForInsertion("Haus", "das ", "de-DE"),
        )
        assertEquals(
            "HAUS",
            HandwritingTextFormatter.textForInsertion("HAUS", "das ", "de-DE"),
        )
    }
}
