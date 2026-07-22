package com.francescooddo.buddygrammar.ime

import android.text.InputType
import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorCapabilitiesTest {
    @Test
    fun `cloud correction dispatch is denied when context degrades during capture`() {
        var capabilities = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.TEXT,
                cloudConsentGranted = true,
            ),
        )
        var dispatches = 0

        val capturedSnapshot = run {
            capabilities = EditorCapabilityPolicy.evaluate(
                EditorPrivacyContext(
                    fieldKind = EditorFieldKind.TEXT,
                    cloudConsentGranted = true,
                    editorCanReadContext = false,
                ),
            )
            "captured text"
        }
        if (capturedSnapshot.isNotEmpty() && capabilities.allowsCloudCorrectionDispatch()) {
            dispatches += 1
        }

        assertFalse(capabilities.allowsCloudCorrectionDispatch())
        assertEquals(0, dispatches)
    }

    @Test
    fun `plain text keeps local intelligence while Buddy and platform services gate independently`() {
        val ready = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.TEXT,
                cloudConsentGranted = true,
                cloudTransportAvailable = true,
                platformVoiceAvailable = true,
                editorCanMoveCursor = true,
                sharedTranscriptAvailable = true,
            ),
        )
        assertAllowed(
            ready.suggestions,
            ready.learning,
            ready.autoCorrection,
            ready.swipe,
            ready.moveCursor,
            ready.starCorrection,
            ready.cloudHandwriting,
            ready.voice,
            ready.pendingTranscript,
            ready.readContext,
            ready.useComposition,
            ready.localHandwriting,
            ready.literalTools,
            ready.directLocalInsertion,
            ready.clipboardInsertion,
        )

        val localOnly = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.TEXT,
                cloudConsentGranted = false,
            ),
        )
        assertAllowed(
            localOnly.suggestions,
            localOnly.learning,
            localOnly.autoCorrection,
            localOnly.swipe,
            localOnly.voice,
            localOnly.pendingTranscript,
        )
        assertDenied(CapabilityDenialReason.CLOUD_CONSENT_REQUIRED, localOnly.starCorrection)
        assertDenied(CapabilityDenialReason.CLOUD_CONSENT_REQUIRED, localOnly.cloudHandwriting)
    }

    @Test
    fun `structured code and sensitive fields deny content assistance but retain cursor movement`() {
        val cases = listOf(
            EditorFieldKind.EMAIL to CapabilityDenialReason.STRUCTURED_FIELD,
            EditorFieldKind.CODE to CapabilityDenialReason.CODE_FIELD,
            EditorFieldKind.PASSWORD to CapabilityDenialReason.SENSITIVE_FIELD,
            EditorFieldKind.ONE_TIME_CODE to CapabilityDenialReason.SENSITIVE_FIELD,
        )

        cases.forEach { (kind, expectedReason) ->
            val capabilities = EditorCapabilityPolicy.evaluate(
                EditorPrivacyContext(fieldKind = kind, cloudConsentGranted = true),
            )
            assertAllowed(capabilities.moveCursor)
            capabilities.intelligenceDecisions().forEach { decision ->
                assertDenied(expectedReason, decision)
            }
            if (kind.isStructured) {
                assertAllowed(
                    capabilities.directLocalInsertion,
                    capabilities.clipboardInsertion,
                )
            } else {
                assertDenied(expectedReason, capabilities.directLocalInsertion)
                assertDenied(expectedReason, capabilities.clipboardInsertion)
            }
        }
    }

    @Test
    fun `search is local only without retaining or sending the query`() {
        val search = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.SEARCH,
                cloudConsentGranted = true,
            ),
        )

        assertAllowed(
            search.suggestions,
            search.autoCorrection,
            search.swipe,
            search.moveCursor,
            search.voice,
        )
        assertDenied(CapabilityDenialReason.STRUCTURED_FIELD, search.learning)
        assertDenied(CapabilityDenialReason.STRUCTURED_FIELD, search.starCorrection)
        assertDenied(CapabilityDenialReason.STRUCTURED_FIELD, search.cloudHandwriting)
        assertDenied(CapabilityDenialReason.STRUCTURED_FIELD, search.pendingTranscript)
    }

    @Test
    fun `structured clipboard is deliberate unless the editor disables assistance`() {
        val email = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(EditorFieldKind.EMAIL, cloudConsentGranted = true),
        )
        assertAllowed(email.clipboardInsertion)

        val editorDisabled = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                EditorFieldKind.EMAIL,
                editorAllowsSuggestions = false,
                cloudConsentGranted = true,
            ),
        )
        assertDenied(
            CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE,
            editorDisabled.clipboardInsertion,
        )
    }

    @Test
    fun `editor no suggestions suppresses prediction and Buddy while platform voice remains available`() {
        val capabilities = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.TEXT,
                editorAllowsSuggestions = false,
                cloudConsentGranted = true,
                platformVoiceAvailable = true,
                sharedTranscriptAvailable = true,
            ),
        )

        listOf(
            capabilities.suggestions,
            capabilities.learning,
            capabilities.autoCorrection,
            capabilities.swipe,
            capabilities.starCorrection,
            capabilities.cloudHandwriting,
        ).forEach {
            assertDenied(CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE, it)
        }
        assertAllowed(capabilities.voice, capabilities.moveCursor)
        assertEquals(EditorFieldKind.LITERAL, capabilities.presentationFieldKind)
        assertDenied(
            CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE,
            capabilities.readContext,
        )
        assertDenied(
            CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE,
            capabilities.useComposition,
        )
        assertAllowed(capabilities.literalTools)
        assertDenied(
            CapabilityDenialReason.EDITOR_DISABLED_ASSISTANCE,
            capabilities.pendingTranscript,
        )
    }

    @Test
    fun `learning voice cursor transport and transcript primitives degrade independently`() {
        val noLearning = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.TEXT,
                editorAllowsPersonalizedLearning = false,
                cloudConsentGranted = true,
            ),
        )
        assertDenied(
            CapabilityDenialReason.EDITOR_DISABLED_PERSONALIZED_LEARNING,
            noLearning.learning,
        )
        assertAllowed(noLearning.suggestions, noLearning.autoCorrection, noLearning.starCorrection)

        val unavailable = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.TEXT,
                cloudConsentGranted = true,
                cloudTransportAvailable = false,
                platformVoiceAvailable = false,
                editorCanMoveCursor = false,
                sharedTranscriptAvailable = false,
            ),
        )
        assertDenied(CapabilityDenialReason.CLOUD_TRANSPORT_UNAVAILABLE, unavailable.starCorrection)
        assertDenied(CapabilityDenialReason.PLATFORM_VOICE_UNAVAILABLE, unavailable.voice)
        assertDenied(CapabilityDenialReason.EDITOR_CURSOR_UNAVAILABLE, unavailable.moveCursor)
        assertDenied(CapabilityDenialReason.SHARED_TRANSCRIPT_UNAVAILABLE, unavailable.pendingTranscript)
        assertAllowed(unavailable.suggestions, unavailable.autoCorrection, unavailable.swipe)
    }

    @Test
    fun `context and composition primitives degrade independently`() {
        val capabilities = EditorCapabilityPolicy.evaluate(
            EditorPrivacyContext(
                fieldKind = EditorFieldKind.TEXT,
                cloudConsentGranted = true,
                editorCanReadContext = false,
                editorCanUseComposition = false,
            ),
        )

        assertAllowed(capabilities.suggestions)
        assertDenied(CapabilityDenialReason.EDITOR_CONTEXT_UNAVAILABLE, capabilities.readContext)
        assertDenied(
            CapabilityDenialReason.EDITOR_COMPOSITION_UNAVAILABLE,
            capabilities.useComposition,
        )
    }

    @Test
    fun `android runtime primitive availability reaches authoritative decisions`() {
        val capabilities = EditorCapabilityPolicy.evaluateAndroid(
            inputType = InputType.TYPE_CLASS_TEXT,
            imeOptions = EditorInfo.IME_ACTION_NONE,
            cloudConsentGranted = true,
            editorCanReadContext = false,
            editorCanUseComposition = false,
        )

        assertDenied(CapabilityDenialReason.EDITOR_CONTEXT_UNAVAILABLE, capabilities.readContext)
        assertDenied(
            CapabilityDenialReason.EDITOR_COMPOSITION_UNAVAILABLE,
            capabilities.useComposition,
        )
    }

    @Test
    fun `android editor traits produce detailed field kinds from the shared catalog`() {
        val cases = listOf(
            AndroidFieldCase("plain", InputType.TYPE_CLASS_TEXT, EditorFieldKind.TEXT),
            AndroidFieldCase(
                "multiline",
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE,
                EditorFieldKind.MULTILINE,
            ),
            AndroidFieldCase(
                "search",
                InputType.TYPE_CLASS_TEXT,
                EditorFieldKind.SEARCH,
                imeOptions = EditorInfo.IME_ACTION_SEARCH,
            ),
            AndroidFieldCase(
                "email",
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                EditorFieldKind.EMAIL,
            ),
            AndroidFieldCase(
                "URL",
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI,
                EditorFieldKind.URL,
            ),
            AndroidFieldCase(
                "name",
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PERSON_NAME,
                EditorFieldKind.NAME,
            ),
            AndroidFieldCase("number", InputType.TYPE_CLASS_NUMBER, EditorFieldKind.NUMBER),
            AndroidFieldCase(
                "decimal",
                InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL,
                EditorFieldKind.DECIMAL,
            ),
            AndroidFieldCase("phone", InputType.TYPE_CLASS_PHONE, EditorFieldKind.PHONE),
            AndroidFieldCase("date-time", InputType.TYPE_CLASS_DATETIME, EditorFieldKind.DATETIME),
            AndroidFieldCase(
                "one-time code",
                InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD,
                EditorFieldKind.ONE_TIME_CODE,
            ),
            AndroidFieldCase(
                "password",
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
                EditorFieldKind.PASSWORD,
            ),
            AndroidFieldCase(
                "code",
                InputType.TYPE_CLASS_TEXT,
                EditorFieldKind.CODE,
                privateImeOptions = "com.example.editor.codeField=true",
            ),
        )

        cases.forEach { case ->
            val capabilities = EditorCapabilityPolicy.evaluateAndroid(
                inputType = case.inputType,
                imeOptions = case.imeOptions,
                privateImeOptions = case.privateImeOptions,
                cloudConsentGranted = true,
            )
            assertEquals(case.name, case.expectedKind, capabilities.fieldKind)
            assertEquals(
                case.name,
                case.expectedKind.catalogFieldKind,
                capabilities.fieldKind.catalogFieldKind,
            )
        }
    }

    private fun assertAllowed(vararg decisions: CapabilityDecision) {
        decisions.forEach { assertTrue(it.isAllowed) }
    }

    private fun assertDenied(
        reason: CapabilityDenialReason,
        decision: CapabilityDecision,
    ) {
        assertEquals(reason, decision.denialReason)
    }

    private fun EditorCapabilities.intelligenceDecisions(): List<CapabilityDecision> = listOf(
        suggestions,
        learning,
        autoCorrection,
        swipe,
        starCorrection,
        cloudHandwriting,
        voice,
        pendingTranscript,
        readContext,
        useComposition,
        localHandwriting,
    )

    private data class AndroidFieldCase(
        val name: String,
        val inputType: Int,
        val expectedKind: EditorFieldKind,
        val imeOptions: Int = EditorInfo.IME_ACTION_NONE,
        val privateImeOptions: String? = null,
    )
}
