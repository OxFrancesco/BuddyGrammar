package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CorrectionCompositionSessionTest {
    @Test
    fun `automatic receipt defers learning and backspace restores literal`() {
        val editor = CorrectionCompositionValueEditor("Please type teh")
        val session = CorrectionCompositionSession(
            initialFieldEpoch = 7,
            fieldIdentifier = "message",
        )

        val applied = session.applyAutomatic(
            editor = editor,
            originalText = "teh",
            replacementText = "the",
            boundaryText = " ",
            precedingContext = "Please type ",
            languageTag = "en-US",
            source = "spelling",
            atMilliseconds = 100,
        )

        assertTrue(applied.didMutateEditor)
        assertEquals("Please type the ", editor.text)
        assertTrue(session.snapshot.hasPendingLearning)

        val reverted = session.backspace(editor)

        assertTrue(reverted.consumedBackspace)
        assertEquals("Please type teh", editor.text)
        assertEquals("spelling", reverted.rejection?.source)
        assertFalse(session.snapshot.hasActiveReceipt)
    }

    @Test
    fun `expiry accepts only while the exact editor observation remains fresh`() {
        val editor = CorrectionCompositionValueEditor("teh")
        val session = CorrectionCompositionSession(fieldIdentifier = "message")
        session.applyAutomatic(
            editor = editor,
            originalText = "teh",
            replacementText = "the",
            boundaryText = " ",
            precedingContext = "",
            languageTag = "en-US",
            source = "spelling",
            atMilliseconds = 100,
            receiptLifetimeMilliseconds = 3_000,
        )

        assertNull(session.advanceTime(3_099, editor).acceptedLearning)
        assertTrue(session.snapshot.hasActiveReceipt)
        assertEquals("the", session.advanceTime(3_100, editor).acceptedLearning?.text)
        assertFalse(session.snapshot.hasActiveReceipt)
    }

    @Test
    fun `continued keyboard typing confirms deferred learning before the edit`() {
        val editor = CorrectionCompositionValueEditor("teh")
        val session = CorrectionCompositionSession(fieldIdentifier = "message")
        session.applyAutomatic(
            editor = editor,
            originalText = "teh",
            replacementText = "the",
            boundaryText = " ",
            precedingContext = "",
            languageTag = "en-US",
            source = "spelling",
            atMilliseconds = 100,
        )

        val confirmation = session.finishActiveReceipt(
            editor = editor,
            acceptLearning = true,
        )
        editor.replaceTextExternally(editor.text + "n")

        assertEquals("the", confirmation.acceptedLearning?.text)
        assertEquals("the n", editor.text)
        assertFalse(session.snapshot.hasActiveReceipt)
    }

    @Test
    fun `field change invalidates receipt and stale async result`() {
        val editor = CorrectionCompositionValueEditor("teh")
        val session = CorrectionCompositionSession(
            initialFieldEpoch = 4,
            fieldIdentifier = "first",
        )
        val stamp = session.captureAsyncStamp()
        session.changeField("second")
        editor.replaceTextExternally("hello")

        val stale = session.applyAsyncAutomatic(
            stamp = stamp,
            editor = editor,
            originalText = "teh",
            replacementText = "the",
            boundaryText = " ",
            precedingContext = "",
            languageTag = "en-US",
            source = "spelling",
            atMilliseconds = 500,
        )

        assertTrue(stale.ignored)
        assertEquals("hello", editor.text)
        assertEquals(5, session.snapshot.fieldEpoch)
    }

    @Test
    fun `successful mutation is reported when host context echo cannot create receipt`() {
        val editor = PostCommitBlindEditor("teh")
        val session = CorrectionCompositionSession(fieldIdentifier = "message")

        val effect = session.applyAutomatic(
            editor = editor,
            originalText = "teh",
            replacementText = "the",
            boundaryText = " ",
            precedingContext = "",
            languageTag = "en-US",
            source = "spelling",
            atMilliseconds = 100,
        )

        assertTrue(effect.didMutateEditor)
        assertTrue(effect.ignored)
        assertEquals("the ", editor.text)
        assertFalse(session.snapshot.hasActiveReceipt)
    }

    @Test
    fun `explicit receipt has visible whole operation undo but not backspace undo`() {
        val editor = CorrectionCompositionValueEditor("i has a cat")
        val session = CorrectionCompositionSession(fieldIdentifier = "message")
        session.applyExplicit(
            editor = editor,
            originalText = "i has a cat",
            replacementText = "I have a cat.",
            source = "buddyFix",
            atMilliseconds = 100,
        )

        val deletion = session.backspace(editor)
        assertFalse(deletion.consumedBackspace)
        assertEquals("I have a cat", editor.text)
        assertFalse(session.snapshot.hasActiveReceipt)

        editor.replaceTextExternally("i has a cat")
        session.applyExplicit(
            editor = editor,
            originalText = "i has a cat",
            replacementText = "I have a cat.",
            source = "buddyFix",
            atMilliseconds = 200,
        )
        val undo = session.visibleRevert(editor)

        assertTrue(undo.didMutateEditor)
        assertEquals("i has a cat", editor.text)
        assertEquals("buddyFix", undo.rejection?.source)
    }
}

private class PostCommitBlindEditor(initialText: String) : CorrectionCompositionEditor {
    var text: String = initialText
        private set
    private var hidesContext = false

    override val correctionCompositionText: String
        get() = if (hidesContext) "" else text

    override fun replaceCorrectionCompositionSuffix(
        expectedSuffix: String,
        replacement: String,
    ): Boolean {
        if (!text.endsWith(expectedSuffix)) return false
        text = text.dropLast(expectedSuffix.length) + replacement
        hidesContext = true
        return true
    }

    override fun deleteCorrectionCompositionBackward(): Boolean = false
}
