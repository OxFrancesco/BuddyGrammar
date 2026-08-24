package com.francescooddo.buddygrammar.ime

import com.francescooddo.buddygrammar.core.CorrectionCompositionRejection
import com.francescooddo.buddygrammar.core.PersonalLanguageModel
import com.francescooddo.buddygrammar.core.SuggestionEngine
import com.francescooddo.buddygrammar.core.SuggestionKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomaticCorrectionRejectionEvidenceTest {
    @Test
    fun `repeated revert evidence protects restored text without permanent pair suppression`() {
        var persisted: String? = null
        val model = PersonalLanguageModel(onPersist = { persisted = it })
        val rejection = CorrectionCompositionRejection(
            source = "spelling",
            rejectedText = "the",
            restoredText = "teh",
            precedingContext = "Please type ",
            languageTag = "en-US",
        )

        repeat(SuggestionEngine.PERSONAL_USAGE_CORRECTION_PROTECTION_THRESHOLD) {
            recordAutomaticCorrectionRejection(model, rejection)
        }

        assertNotNull(persisted)
        val reloaded = PersonalLanguageModel(persisted)
        assertEquals(
            SuggestionEngine.PERSONAL_USAGE_CORRECTION_PROTECTION_THRESHOLD,
            reloaded.usageCount("teh", "en-US"),
        )
        assertEquals(0, reloaded.usageCount("the", "en-US"))
        assertFalse(reloaded.isCorrectionSuppressed("teh", "the", "en-US"))
        assertFalse(reloaded.isCorrectionSuppressed("teh", "the", "it-IT"))
        assertTrue(
            SuggestionEngine.suggest("teh", reloaded, "en-US")
                .none { it.kind == SuggestionKind.CORRECTION },
        )
    }
}
