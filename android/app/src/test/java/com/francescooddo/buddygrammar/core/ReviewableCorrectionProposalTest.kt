package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReviewableCorrectionProposalTest {
    @Test
    fun `proposal preserves original and computes a bounded diff`() {
        val proposal = ReviewableCorrectionProposal(
            intent = BuddyRewriteIntent.SHORTEN,
            originalText = "This is a very long sentence.",
            proposedText = "This sentence is long.",
        )

        assertTrue(proposal.hasChanges)
        assertEquals("is a very long sentence", proposal.change.originalChangedText)
        assertEquals("sentence is long", proposal.change.proposedChangedText)
    }

    @Test
    fun `identical output is a no change proposal`() {
        val proposal = ReviewableCorrectionProposal(
            intent = BuddyRewriteIntent.FIX,
            originalText = "Already correct.",
            proposedText = "Already correct.",
        )

        assertFalse(proposal.hasChanges)
        assertEquals("", proposal.change.originalChangedText)
        assertEquals("", proposal.change.proposedChangedText)
    }

    @Test
    fun `bounded diff never splits supplementary emoji surrogate pairs`() {
        val proposal = ReviewableCorrectionProposal(
            intent = BuddyRewriteIntent.CLEARER,
            originalText = "Ready 🚀 today",
            proposedText = "Ready 🚀 tomorrow",
        )

        assertEquals("Ready 🚀 to", proposal.change.commonPrefix)
        assertEquals("day", proposal.change.originalChangedText)
        assertEquals("morrow", proposal.change.proposedChangedText)
        listOf(
            proposal.change.commonPrefix,
            proposal.change.originalChangedText,
            proposal.change.proposedChangedText,
            proposal.change.commonSuffix,
        ).forEach { span ->
            assertFalse(span.hasUnpairedSurrogate())
        }
    }

    @Test
    fun `bounded diff keeps zwj emoji and combining sequences whole`() {
        val family = "👨‍👩‍👧‍👦"
        val accented = "e\u0301"
        val proposal = ReviewableCorrectionProposal(
            intent = BuddyRewriteIntent.FIX,
            originalText = "A$family$accented old",
            proposedText = "A$family$accented new",
        )

        assertEquals("A$family$accented ", proposal.change.commonPrefix)
        assertEquals("old", proposal.change.originalChangedText)
        assertEquals("new", proposal.change.proposedChangedText)
    }

    @Test
    fun `changing one supplementary emoji yields two complete changed spans`() {
        val proposal = ReviewableCorrectionProposal(
            intent = BuddyRewriteIntent.FRIENDLY,
            originalText = "Mood 😀!",
            proposedText = "Mood 😁!",
        )

        assertEquals("Mood ", proposal.change.commonPrefix)
        assertEquals("😀", proposal.change.originalChangedText)
        assertEquals("😁", proposal.change.proposedChangedText)
        assertEquals("!", proposal.change.commonSuffix)
        assertFalse(proposal.change.originalChangedText.hasUnpairedSurrogate())
        assertFalse(proposal.change.proposedChangedText.hasUnpairedSurrogate())
    }

    @Test
    fun `all intents return a bounded replacement instruction`() {
        BuddyRewriteIntent.entries.forEach { intent ->
            val instruction = intent.instruction("Keep meaning.")
            assertTrue(instruction.startsWith("Keep meaning."))
            assertTrue(instruction.contains("Return only"))
        }
    }

    private fun String.hasUnpairedSurrogate(): Boolean {
        var index = 0
        while (index < length) {
            val character = this[index]
            when {
                character.isHighSurrogate() -> {
                    if (index + 1 >= length || !this[index + 1].isLowSurrogate()) return true
                    index += 2
                }
                character.isLowSurrogate() -> return true
                else -> index += 1
            }
        }
        return false
    }
}
