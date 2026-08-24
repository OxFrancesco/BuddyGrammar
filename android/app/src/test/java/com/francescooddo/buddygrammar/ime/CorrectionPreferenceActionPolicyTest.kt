package com.francescooddo.buddygrammar.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo
import com.francescooddo.buddygrammar.core.AutomaticSuggestionReplacement
import com.francescooddo.buddygrammar.core.AutomaticSuggestionSource
import com.francescooddo.buddygrammar.core.CorrectionCandidatePreference
import com.francescooddo.buddygrammar.core.Suggestion
import com.francescooddo.buddygrammar.core.SuggestionKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CorrectionPreferenceActionPolicyTest {
    @Test
    fun `no personalized learning flag performs zero context reads and zero writes`() {
        val capabilities = EditorCapabilityPolicy.evaluateAndroid(
            inputType = InputType.TYPE_CLASS_TEXT,
            imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING,
            cloudConsentGranted = true,
        )
        var contextReads = 0
        var writes = 0

        val result = CorrectionPreferenceActionPolicy.perform(
            capabilities = capabilities,
            suggestion = correctionSuggestion(),
            currentFieldEpoch = 4,
            currentFieldIdentifier = "field-a",
            currentLanguageTag = "en-US",
            contextBeforeCursor = {
                contextReads += 1
                "Please type teh"
            },
            persist = {
                writes += 1
                true
            },
        )

        assertTrue(result is CorrectionPreferenceActionResult.Denied)
        assertFalse(
            CorrectionPreferenceActionPolicy.canOffer(
                capabilities = capabilities,
                suggestion = correctionSuggestion(),
                currentFieldEpoch = 4,
                currentFieldIdentifier = "field-a",
                currentLanguageTag = "en-US",
            ),
        )
        assertEquals(0, contextReads)
        assertEquals(0, writes)
    }

    @Test
    fun `stale field menu action performs zero context reads and zero writes`() {
        var contextReads = 0
        var writes = 0

        val result = CorrectionPreferenceActionPolicy.perform(
            capabilities = allowedCapabilities(),
            suggestion = correctionSuggestion(fieldEpoch = 3, fieldIdentifier = "field-a"),
            currentFieldEpoch = 4,
            currentFieldIdentifier = "field-b",
            currentLanguageTag = "en-US",
            contextBeforeCursor = {
                contextReads += 1
                "Please type teh"
            },
            persist = {
                writes += 1
                true
            },
        )

        assertTrue(result is CorrectionPreferenceActionResult.Denied)
        assertEquals(0, contextReads)
        assertEquals(0, writes)
    }

    @Test
    fun `stale language menu action performs zero context reads and zero writes`() {
        var contextReads = 0
        var writes = 0

        val result = CorrectionPreferenceActionPolicy.perform(
            capabilities = allowedCapabilities(),
            suggestion = correctionSuggestion(),
            currentFieldEpoch = 4,
            currentFieldIdentifier = "field-a",
            currentLanguageTag = "it-IT",
            contextBeforeCursor = {
                contextReads += 1
                "Please type teh"
            },
            persist = {
                writes += 1
                true
            },
        )

        assertTrue(result is CorrectionPreferenceActionResult.Denied)
        assertEquals(0, contextReads)
        assertEquals(0, writes)
    }

    @Test
    fun `changed context menu action performs zero writes`() {
        var writes = 0

        val result = CorrectionPreferenceActionPolicy.perform(
            capabilities = allowedCapabilities(),
            suggestion = correctionSuggestion(),
            currentFieldEpoch = 4,
            currentFieldIdentifier = "field-a",
            currentLanguageTag = "en-US",
            contextBeforeCursor = { "Someone else typed teh" },
            persist = {
                writes += 1
                true
            },
        )

        assertTrue(result is CorrectionPreferenceActionResult.Denied)
        assertEquals(0, writes)
    }

    @Test
    fun `fresh action persists the exact captured pair once`() {
        var persisted: CorrectionCandidatePreference? = null

        val result = CorrectionPreferenceActionPolicy.perform(
            capabilities = allowedCapabilities(),
            suggestion = correctionSuggestion(),
            currentFieldEpoch = 4,
            currentFieldIdentifier = "field-a",
            currentLanguageTag = "en-US",
            contextBeforeCursor = { "Please type teh" },
            persist = { target ->
                persisted = target
                true
            },
        )

        assertTrue(result is CorrectionPreferenceActionResult.Applied)
        assertEquals(
            CorrectionCandidatePreference("teh", "the", "en-US"),
            persisted,
        )
    }

    private fun correctionSuggestion(
        fieldEpoch: Long = 4,
        fieldIdentifier: String = "field-a",
    ): Suggestion = Suggestion(
        text = "the",
        replaceBeforeCursor = 3,
        appendSpace = true,
        kind = SuggestionKind.CORRECTION,
        automaticReplacement = requireNotNull(
            AutomaticSuggestionReplacement.create(
                originalText = "teh",
                replacementText = "the",
                boundaryText = " ",
                precedingContext = "Please type ",
                source = AutomaticSuggestionSource.SPELLING,
            ),
        ).ownedBy(
            fieldEpoch = fieldEpoch,
            fieldIdentifier = fieldIdentifier,
            languageTag = "en-US",
        ),
    )

    private fun allowedCapabilities(): EditorCapabilities =
        EditorCapabilityPolicy.evaluateAndroid(
            inputType = InputType.TYPE_CLASS_TEXT,
            imeOptions = 0,
            cloudConsentGranted = true,
        )
}
