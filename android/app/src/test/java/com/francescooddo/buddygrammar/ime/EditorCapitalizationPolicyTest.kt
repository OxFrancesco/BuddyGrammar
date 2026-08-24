package com.francescooddo.buddygrammar.ime

import android.text.InputType
import android.text.TextUtils
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorCapitalizationPolicyTest {
    @Test
    fun `android text capitalization flags map to their exact modes`() {
        assertEquals(
            EditorCapitalizationMode.SENTENCES,
            EditorCapitalizationPolicy.mode(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES,
                EditorFieldKind.TEXT,
            ),
        )
        assertEquals(
            EditorCapitalizationMode.WORDS,
            EditorCapitalizationPolicy.mode(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_WORDS,
                EditorFieldKind.NAME,
            ),
        )
        assertEquals(
            EditorCapitalizationMode.CHARACTERS,
            EditorCapitalizationPolicy.mode(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS,
                EditorFieldKind.TEXT,
            ),
        )
    }

    @Test
    fun `email URL and code fields never auto capitalize even when editors request it`() {
        val allFlags = InputType.TYPE_CLASS_TEXT or
            InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or
            InputType.TYPE_TEXT_FLAG_CAP_WORDS or
            InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS

        listOf(EditorFieldKind.EMAIL, EditorFieldKind.URL, EditorFieldKind.CODE).forEach { kind ->
            assertEquals(kind.name, EditorCapitalizationMode.NONE, EditorCapitalizationPolicy.mode(allFlags, kind))
        }
    }

    @Test
    fun `keyboard session refreshes shift according to sentence word and character modes`() {
        val state = KeyboardState()

        state.configureForNewInput(startOnNumbers = false, autoCapitalize = false)
        state.updateAutoShift("Hello. ", EditorCapitalizationMode.SENTENCES)
        assertTrue(state.shift)
        state.updateAutoShift("Hello", EditorCapitalizationMode.SENTENCES)
        assertFalse(state.shift)

        state.updateAutoShift("two ", EditorCapitalizationMode.WORDS)
        assertTrue(state.shift)
        state.updateAutoShift("tw", EditorCapitalizationMode.WORDS)
        assertFalse(state.shift)

        state.updateAutoShift("anything", EditorCapitalizationMode.CHARACTERS)
        assertTrue(state.shift)
        state.updateAutoShift("", EditorCapitalizationMode.NONE)
        assertFalse(state.shift)
    }

    @Test
    fun `unknown context preserves shift while explicit empty context starts a sentence`() {
        val state = KeyboardState()
        state.configureForNewInput(startOnNumbers = false, autoCapitalize = false)

        state.updateAutoShift(null, EditorCapitalizationMode.SENTENCES)
        assertFalse(state.shift)

        state.onShiftTapped()
        assertTrue(state.shift)
        state.updateAutoShift(null, EditorCapitalizationMode.SENTENCES)
        assertTrue(state.shift)

        state.onCharacterCommitted()
        assertFalse(state.shift)
        state.updateAutoShift("", EditorCapitalizationMode.SENTENCES)
        assertTrue(state.shift)
    }

    @Test
    fun `unknown person-name context does not capitalize an existing all-caps word`() {
        val mode = EditorCapitalizationPolicy.mode(
            InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_VARIATION_PERSON_NAME or
                InputType.TYPE_TEXT_FLAG_CAP_WORDS,
            EditorFieldKind.NAME,
        )
        val state = KeyboardState()
        state.configureForNewInput(startOnNumbers = false, autoCapitalize = true)

        state.updateAutoShift("JOHN", mode)
        assertFalse(state.shift)
        state.updateAutoShift(null, mode)
        assertFalse(state.shift)
    }

    @Test
    fun `practice suppresses suggestions but still refreshes sentence capitalization`() {
        val plan = KeyboardRefreshPolicy.plan(
            suggestionsAllowed = true,
            readContextAllowed = true,
            practiceActive = true,
        )
        val state = KeyboardState()
        state.configureForNewInput(startOnNumbers = false, autoCapitalize = false)

        assertTrue(plan.shouldReadContext)
        assertFalse(plan.shouldShowSuggestions)
        if (plan.shouldReadContext) {
            state.updateAutoShift("Practice sentence. ", EditorCapitalizationMode.SENTENCES)
        }
        assertTrue(state.shift)
    }

    @Test
    fun `name field re-enables shift after John space without reading intelligence context`() {
        val mode = EditorCapitalizationPolicy.mode(
            InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_VARIATION_PERSON_NAME or
                InputType.TYPE_TEXT_FLAG_CAP_WORDS or
                InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS,
            EditorFieldKind.NAME,
        )
        val plan = KeyboardRefreshPolicy.plan(
            suggestionsAllowed = false,
            readContextAllowed = false,
            practiceActive = false,
        )
        val state = KeyboardState()
        state.configureForNewInput(startOnNumbers = false, autoCapitalize = true)

        state.onCharacterCommitted()
        assertFalse(state.shift)
        assertFalse(plan.shouldReadContext)
        assertTrue(plan.shouldQueryCursorCapsMode)
        assertEquals(TextUtils.CAP_MODE_WORDS, mode.cursorCapsModeRequest)

        // The editor reports CAP_WORDS after the owned literal sequence "John ".
        state.updateAutoShiftFromCursorCapsMode(TextUtils.CAP_MODE_WORDS)
        assertTrue(state.shift)

        state.onCharacterCommitted()
        state.updateAutoShiftFromCursorCapsMode(null)
        assertFalse("unknown caps context must not force capitalization", state.shift)
    }

    @Test
    fun `failed planned context read immediately falls back to editor caps mode`() {
        val plan = KeyboardRefreshPolicy.plan(
            suggestionsAllowed = true,
            readContextAllowed = true,
            practiceActive = false,
        )
        val state = KeyboardState()
        state.configureForNewInput(startOnNumbers = false, autoCapitalize = false)

        assertTrue(plan.shouldReadContext)
        assertTrue(plan.shouldUseCursorCapsMode(contextReadSucceeded = false))
        state.updateAutoShiftFromCursorCapsMode(TextUtils.CAP_MODE_SENTENCES)

        assertTrue(state.shift)
    }
}
