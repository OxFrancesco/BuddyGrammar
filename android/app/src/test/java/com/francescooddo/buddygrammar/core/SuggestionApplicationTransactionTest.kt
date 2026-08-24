package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SuggestionApplicationTransactionTest {
    @Test
    fun `stale completion row performs zero mutation and zero learning`() {
        val suggestion = renderedSuggestion(
            kind = SuggestionKind.COMPLETION,
            text = "hello",
            replaceBeforeCursor = 3,
            context = "Say hel",
        )
        val editor = RecordingSuggestionEditor("Say help")
        var learningEvents = 0

        val effect = SuggestionApplicationTransaction.apply(
            suggestion = suggestion,
            currentFieldEpoch = 7,
            currentFieldIdentifier = "field-a",
            currentLanguageTag = "en-US",
            editor = editor,
            onCommitted = { learningEvents += 1 },
        )

        assertFalse(effect.didMutateEditor)
        assertEquals(0, editor.deleteCalls)
        assertEquals(0, editor.commitCalls)
        assertEquals(0, learningEvents)
    }

    @Test
    fun `stale emoji row performs zero context reads mutation and learning`() {
        val suggestion = renderedSuggestion(
            kind = SuggestionKind.EMOJI,
            text = "🙂",
            replaceBeforeCursor = 5,
            context = "Say smile",
        )
        val editor = RecordingSuggestionEditor("Say smile")
        var learningEvents = 0

        val effect = SuggestionApplicationTransaction.apply(
            suggestion = suggestion,
            currentFieldEpoch = 8,
            currentFieldIdentifier = "field-b",
            currentLanguageTag = "en-US",
            editor = editor,
            onCommitted = { learningEvents += 1 },
        )

        assertFalse(effect.didMutateEditor)
        assertEquals(0, editor.readCalls)
        assertEquals(0, editor.deleteCalls)
        assertEquals(0, editor.commitCalls)
        assertEquals(0, learningEvents)
    }

    @Test
    fun `stale prediction row performs zero mutation and zero learning`() {
        val suggestion = renderedSuggestion(
            kind = SuggestionKind.PREDICTION,
            text = "you",
            replaceBeforeCursor = 0,
            context = "Thank ",
        )
        val editor = RecordingSuggestionEditor("Other ")
        var learningEvents = 0

        val effect = SuggestionApplicationTransaction.apply(
            suggestion = suggestion,
            currentFieldEpoch = 7,
            currentFieldIdentifier = "field-a",
            currentLanguageTag = "en-US",
            editor = editor,
            onCommitted = { learningEvents += 1 },
        )

        assertFalse(effect.didMutateEditor)
        assertEquals(0, editor.deleteCalls)
        assertEquals(0, editor.commitCalls)
        assertEquals(0, learningEvents)
    }

    @Test
    fun `destructive receipt needs an in-window word boundary or owned suffix`() {
        val truncatedAtTarget = suggestion(
            kind = SuggestionKind.COMPLETION,
            text = "suffixes",
            replaceBeforeCursor = 6,
        )

        assertNull(capture(truncatedAtTarget, context = "suffix"))
        assertNull(capture(truncatedAtTarget, context = "longsuffix"))
        assertNotNull(capture(truncatedAtTarget, context = " suffix"))
        assertNotNull(
            capture(
                truncatedAtTarget,
                context = "suffix",
                keyboardOwnedSuffix = "suffix",
            ),
        )
    }

    @Test
    fun `destructive receipt rejects a target start inside a surrogate pair`() {
        val suggestion = suggestion(
            kind = SuggestionKind.EMOJI,
            text = "🙂",
            replaceBeforeCursor = 2,
        )

        // UTF-16 index 2 is between the high and low surrogate of 😀.
        assertNull(capture(suggestion, context = " 😀x"))
    }

    @Test
    fun `long-word truncated tail authorizes zero mutation and zero learning`() {
        var mutations = 0
        var learningEvents = 0

        // InputConnection may return only this correctable suffix of a much longer word.
        SuggestionTargetBoundaryPolicy.proof(
            contextBeforeCursor = "teh",
            replaceBeforeCursor = 3,
        )?.let {
            mutations += 1
            learningEvents += 1
        }

        assertEquals(0, mutations)
        assertEquals(0, learningEvents)
    }

    @Test
    fun `matching capped taps do not own a suffix without proven composition start`() {
        val contextBeforeFirstTap = "x".repeat(64)
        val startedAtBoundary = KeyboardOwnedWordProvenancePolicy.startedAtProvenBoundary(
            contextBeforeFirstTap = contextBeforeFirstTap,
            selectionStart = 200,
        )

        assertFalse(startedAtBoundary)
        assertFalse(
            KeyboardOwnedWordProvenancePolicy.ownsCurrentWord(
                rawCurrentWord = "teh",
                resolvedTapPath = "teh",
                startedAtProvenBoundary = startedAtBoundary,
            ),
        )
        assertTrue(
            KeyboardOwnedWordProvenancePolicy.startedAtProvenBoundary(
                contextBeforeFirstTap = "Type ",
                selectionStart = 5,
            ),
        )
        assertTrue(
            KeyboardOwnedWordProvenancePolicy.startedAtProvenBoundary(
                contextBeforeFirstTap = "",
                selectionStart = 0,
            ),
        )
    }

    @Test
    fun `fresh completion mutates once and reports exact captured learning prefix`() {
        val suggestion = renderedSuggestion(
            kind = SuggestionKind.COMPLETION,
            text = "hello",
            replaceBeforeCursor = 3,
            context = "Say hel",
        )
        val editor = RecordingSuggestionEditor("Say hel")
        var committed: SuggestionCommittedContext? = null

        val effect = SuggestionApplicationTransaction.apply(
            suggestion = suggestion,
            currentFieldEpoch = 7,
            currentFieldIdentifier = "field-a",
            currentLanguageTag = "en-US",
            editor = editor,
            onCommitted = { committed = it },
        )

        assertTrue(effect.didMutateEditor)
        assertEquals(1, editor.deleteCalls)
        assertEquals(1, editor.commitCalls)
        assertEquals("Say hello ", editor.context)
        assertEquals(
            SuggestionCommittedContext(
                text = "hello",
                precedingContext = "Say ",
                languageTag = "en-US",
            ),
            committed,
        )
    }

    private fun renderedSuggestion(
        kind: SuggestionKind,
        text: String,
        replaceBeforeCursor: Int,
        context: String,
    ): Suggestion {
        val suggestion = suggestion(kind, text, replaceBeforeCursor)
        return suggestion.copy(
            renderReceipt = requireNotNull(capture(suggestion, context)),
        )
    }

    private fun suggestion(
        kind: SuggestionKind,
        text: String,
        replaceBeforeCursor: Int,
    ) = Suggestion(
        text = text,
        replaceBeforeCursor = replaceBeforeCursor,
        appendSpace = kind != SuggestionKind.EMOJI,
        kind = kind,
    )

    private fun capture(
        suggestion: Suggestion,
        context: String,
        keyboardOwnedSuffix: String? = null,
    ): SuggestionRenderReceipt? = SuggestionRenderReceipt.capture(
        suggestion = suggestion,
        contextBeforeCursor = context,
        maximumContextLength = 128,
        fieldEpoch = 7,
        fieldIdentifier = "field-a",
        languageTag = "en-US",
        keyboardOwnedSuffix = keyboardOwnedSuffix,
    )

    private class RecordingSuggestionEditor(
        var context: String?,
    ) : SuggestionApplicationEditor {
        var readCalls = 0
        var deleteCalls = 0
        var commitCalls = 0

        override fun beginBatchEdit() = Unit

        override fun contextBeforeCursor(maximumCharacters: Int): String? {
            readCalls += 1
            return context?.takeLast(maximumCharacters)
        }

        override fun deleteBeforeCursor(characters: Int): Boolean {
            deleteCalls += 1
            val current = context ?: return false
            if (characters > current.length) return false
            context = current.dropLast(characters)
            return true
        }

        override fun commitText(text: String): Boolean {
            commitCalls += 1
            context = context.orEmpty() + text
            return true
        }

        override fun endBatchEdit() = Unit
    }
}
