package com.francescooddo.buddygrammar.ime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EditorContextAccessGateTest {
    @Test
    fun `denied context capability performs zero editor reads`() {
        var reads = 0

        val value = EditorContextAccessGate.read(
            CapabilityDecision.denied(CapabilityDenialReason.SENSITIVE_FIELD),
        ) {
            reads += 1
            "secret"
        }

        assertNull(value)
        assertEquals(0, reads)
    }

    @Test
    fun `allowed context capability reads exactly once`() {
        var reads = 0

        val value = EditorContextAccessGate.read(CapabilityDecision.ALLOWED) {
            reads += 1
            "ordinary text"
        }

        assertEquals("ordinary text", value)
        assertEquals(1, reads)
    }

    @Test
    fun `sensitive structured code and no suggestion policies perform zero reads`() {
        val contexts = listOf(
            EditorPrivacyContext(EditorFieldKind.PASSWORD, cloudConsentGranted = true),
            EditorPrivacyContext(EditorFieldKind.ONE_TIME_CODE, cloudConsentGranted = true),
            EditorPrivacyContext(EditorFieldKind.CODE, cloudConsentGranted = true),
            EditorPrivacyContext(EditorFieldKind.EMAIL, cloudConsentGranted = true),
            EditorPrivacyContext(
                EditorFieldKind.TEXT,
                editorAllowsSuggestions = false,
                cloudConsentGranted = true,
            ),
        )

        contexts.forEach { context ->
            var spyReads = 0
            val capabilities = EditorCapabilityPolicy.evaluate(context)

            val value = EditorContextAccessGate.read(capabilities.readContext) {
                spyReads += 1
                "must never be observed"
            }

            assertNull(context.fieldKind.name, value)
            assertEquals(context.fieldKind.name, 0, spyReads)
        }
    }

    @Test
    fun `failed adaptive context read commits exactly one literal and performs no adaptive work`() {
        val committed = mutableListOf<String>()
        var adaptiveContinuations = 0

        AdaptiveCharacterContextDispatch.dispatch(
            literalValue = "x",
            contextBeforeCursor = null,
            commitLiteral = committed::add,
            continueAdaptive = { adaptiveContinuations += 1 },
        )

        assertEquals(listOf("x"), committed)
        assertEquals(0, adaptiveContinuations)
    }
}
