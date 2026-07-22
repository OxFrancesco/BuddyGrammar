package com.francescooddo.buddygrammar.core.adaptive

/** Shared production thresholds for tap suggestions and automatic correction. */
enum class TapWordAcceptancePolicy(
    val minimumConfidence: Double,
    val minimumMargin: Double,
) {
    SUGGESTION(minimumConfidence = 0.38, minimumMargin = 0.08),
    AUTOMATIC(minimumConfidence = 0.50, minimumMargin = 0.18),
    ;

    fun acceptedCandidate(result: TapWordDecodingResult): TapWordCandidate? {
        val best = result.candidates.firstOrNull() ?: return null
        return best.takeIf {
            it.confidence >= minimumConfidence &&
                result.margin >= minimumMargin &&
                !it.word.equals(result.literalWord, ignoreCase = true)
        }
    }

    /**
     * Selects a production replacement through the same suppression seam as
     * spelling suggestions. This prevents tap-lattice candidates from
     * bypassing a user's explicit "Never suggest" decision.
     */
    fun acceptedReplacement(
        result: TapWordDecodingResult,
        visibleWord: String,
        isSuppressed: (typed: String, suggestion: String) -> Boolean,
    ): String? {
        val replacement = acceptedCandidate(result)?.word ?: return null
        return replacement.takeUnless {
            it.equals(visibleWord, ignoreCase = true) ||
                isSuppressed(visibleWord, it)
        }
    }
}
