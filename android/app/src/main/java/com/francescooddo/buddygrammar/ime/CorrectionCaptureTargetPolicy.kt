package com.francescooddo.buddygrammar.ime

internal enum class CorrectionCaptureTarget {
    SELECTION,
    CURRENT_SENTENCE,
    UNAVAILABLE,
}

/** Keeps cloud correction scoped to the user's known editor selection. */
internal object CorrectionCaptureTargetPolicy {
    fun target(
        selectionStart: Int,
        selectionEnd: Int,
        hasSelectedCandidate: Boolean,
    ): CorrectionCaptureTarget {
        if (hasSelectedCandidate) return CorrectionCaptureTarget.SELECTION
        val hasKnownSelection = selectionStart >= 0 &&
            selectionEnd >= 0 &&
            selectionStart != selectionEnd
        return if (hasKnownSelection) {
            CorrectionCaptureTarget.UNAVAILABLE
        } else {
            CorrectionCaptureTarget.CURRENT_SENTENCE
        }
    }
}
