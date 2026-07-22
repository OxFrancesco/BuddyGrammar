package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class LocalCorrectionReceiptTest {
    @Test
    fun `immediate backspace restores the literal word and carries explicit rejection evidence`() {
        val receipt = LocalCorrectionReceipt.create(
            originalText = "teh",
            replacementText = "the",
            contextBeforeOriginal = "Please type ",
            boundaryText = " ",
            languageTag = "en-US",
        )

        val revert = receipt.revertPlan(
            contextBeforeCursor = "Please type the ",
            mode = LocalCorrectionRevertMode.BACKSPACE,
        )

        assertNotNull(revert)
        assertEquals(4, revert?.deleteBeforeCursor)
        assertEquals("teh", revert?.insertText)
        assertEquals("the", revert?.rejection?.rejectedWord)
        assertEquals(listOf("Please", "type"), revert?.rejection?.contextWords)
        assertEquals("en-US", revert?.rejection?.languageTag)

        val personalModel = PersonalLanguageModel()
        personalModel.learnCommittedText("the", "Please type ", "en-US")
        revert?.rejection?.recordIn(personalModel)
        assertEquals(0, personalModel.usageCount("the", "en-US"))
    }

    @Test
    fun `visible undo restores the literal while preserving the committed boundary`() {
        val receipt = LocalCorrectionReceipt.create(
            originalText = "teh",
            replacementText = "the",
            contextBeforeOriginal = "Please type ",
            boundaryText = " ",
            languageTag = "en-US",
        )

        val revert = receipt.revertPlan(
            contextBeforeCursor = "Please type the ",
            mode = LocalCorrectionRevertMode.VISIBLE_UNDO,
        )

        assertNotNull(revert)
        assertEquals(4, revert?.deleteBeforeCursor)
        assertEquals("teh ", revert?.insertText)
    }

    @Test
    fun `receipt refuses to revert after surrounding text changes`() {
        val receipt = LocalCorrectionReceipt.create(
            originalText = "teh",
            replacementText = "the",
            contextBeforeOriginal = "Please type ",
            boundaryText = " ",
            languageTag = "en-US",
        )

        assertNull(receipt.revertPlan("Someone else edited the "))
        assertNull(receipt.revertPlan("Please type the next "))
    }

    @Test
    fun `receipt carries deferred acceptance evidence for the corrected word`() {
        val receipt = LocalCorrectionReceipt.create(
            originalText = "teh",
            replacementText = "the",
            contextBeforeOriginal = "Please type ",
            boundaryText = " ",
            languageTag = "en-US",
        )
        val model = PersonalLanguageModel()

        assertEquals(0, model.usageCount("the", "en-US"))
        receipt.acceptance.recordIn(model)

        assertEquals(1, model.usageCount("the", "en-US"))
        assertEquals(listOf("Please", "type"), receipt.acceptance.contextWords)
    }
}
