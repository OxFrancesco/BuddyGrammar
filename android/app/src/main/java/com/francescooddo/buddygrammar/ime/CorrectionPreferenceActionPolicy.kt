package com.francescooddo.buddygrammar.ime

import com.francescooddo.buddygrammar.core.CorrectionCandidatePreference
import com.francescooddo.buddygrammar.core.Suggestion
import com.francescooddo.buddygrammar.core.SuggestionKind

internal sealed interface CorrectionPreferenceActionResult {
    data class Denied(val message: String) : CorrectionPreferenceActionResult

    data class Applied(
        val target: CorrectionCandidatePreference,
        val changed: Boolean,
    ) : CorrectionPreferenceActionResult
}

/** Fail-closed authorization at the personalized-model persistence seam. */
internal object CorrectionPreferenceActionPolicy {
    fun canOffer(
        capabilities: EditorCapabilities,
        suggestion: Suggestion,
        currentFieldEpoch: Long,
        currentFieldIdentifier: String,
        currentLanguageTag: String,
    ): Boolean = capabilityDenial(capabilities) == null &&
        suggestion.kind == SuggestionKind.CORRECTION &&
        suggestion.automaticReplacement?.isOwnedBy(
            fieldEpoch = currentFieldEpoch,
            fieldIdentifier = currentFieldIdentifier,
            languageTag = currentLanguageTag,
        ) == true

    fun perform(
        capabilities: EditorCapabilities,
        suggestion: Suggestion,
        currentFieldEpoch: Long,
        currentFieldIdentifier: String,
        currentLanguageTag: String,
        contextBeforeCursor: () -> String?,
        persist: (CorrectionCandidatePreference) -> Boolean,
    ): CorrectionPreferenceActionResult {
        capabilityDenial(capabilities)?.let {
            return CorrectionPreferenceActionResult.Denied(it)
        }
        val replacement = suggestion.automaticReplacement
        if (
            suggestion.kind != SuggestionKind.CORRECTION || replacement == null ||
            !replacement.isOwnedBy(
                fieldEpoch = currentFieldEpoch,
                fieldIdentifier = currentFieldIdentifier,
                languageTag = currentLanguageTag,
            )
        ) {
            return staleDenial()
        }

        val observedContext = contextBeforeCursor() ?: return CorrectionPreferenceActionResult.Denied(
            "This correction cannot be saved because editor context is unavailable.",
        )
        val insertion = suggestion.text + if (suggestion.appendSpace) " " else ""
        if (
            !replacement.matches(
                contextBeforeCursor = observedContext,
                replaceBeforeCursor = suggestion.replaceBeforeCursor,
                insertion = insertion,
            )
        ) {
            return staleDenial()
        }

        val target = CorrectionCandidatePreference(
            typedText = replacement.originalText,
            suggestedText = replacement.replacementText,
            languageTag = requireNotNull(replacement.renderedLanguageTag),
        )
        return CorrectionPreferenceActionResult.Applied(
            target = target,
            changed = persist(target),
        )
    }

    private fun capabilityDenial(capabilities: EditorCapabilities): String? {
        val denied = listOf(
            capabilities.suggestions,
            capabilities.learning,
            capabilities.readContext,
        ).firstOrNull { !it.isAllowed } ?: return null
        return denied.denialMessage("Correction preferences")
    }

    private fun staleDenial() = CorrectionPreferenceActionResult.Denied(
        "This correction is no longer valid in the current field.",
    )
}
