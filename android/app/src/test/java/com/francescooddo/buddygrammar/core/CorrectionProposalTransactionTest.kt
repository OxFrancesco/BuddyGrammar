package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CorrectionProposalTransactionTest {
    @Test
    fun `fresh stamped proposal exposes review metadata and replacement`() {
        val stamp = CorrectionProposalEditorStamp(
            fieldEpoch = 7,
            selectedText = "I has apples",
            textBeforeCursor = "Hello ",
            textAfterCursor = " today",
        )
        val transaction = CorrectionProposalTransaction(
            proposal = ReviewableCorrectionProposal(
                intent = BuddyRewriteIntent.FIX,
                originalText = "I has apples",
                proposedText = "I have apples",
            ),
            scope = CorrectionProposalScope.SELECTION,
            stamp = stamp,
        )

        assertEquals("I have apples", transaction.replacementIfFresh(stamp))
        assertEquals("Selection", transaction.scope.displayName)
        assertTrue(transaction.cloudProcessed)
        assertEquals("s", transaction.proposal.change.originalChangedText)
        assertEquals("ve", transaction.proposal.change.proposedChangedText)
    }

    @Test
    fun `accept rejects a stale field context or selection`() {
        val original = CorrectionProposalEditorStamp(
            fieldEpoch = 3,
            selectedText = null,
            textBeforeCursor = "Please send teh file.",
            textAfterCursor = " Next sentence.",
        )
        val transaction = CorrectionProposalTransaction(
            proposal = ReviewableCorrectionProposal(
                intent = BuddyRewriteIntent.FIX,
                originalText = "Please send teh file.",
                proposedText = "Please send the file.",
            ),
            scope = CorrectionProposalScope.CURRENT_SENTENCE,
            stamp = original,
        )

        assertNull(transaction.replacementIfFresh(original.copy(fieldEpoch = 4)))
        assertNull(transaction.replacementIfFresh(original.copy(textBeforeCursor = "Edited")))
        assertNull(transaction.replacementIfFresh(original.copy(selectedText = "selection")))
        assertFalse(transaction.isFreshFor(null))
    }
}
