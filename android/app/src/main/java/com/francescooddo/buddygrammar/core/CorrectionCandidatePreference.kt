package com.francescooddo.buddygrammar.core

data class CorrectionCandidatePreference(
    val typedText: String,
    val suggestedText: String,
    val languageTag: String,
)

object CorrectionCandidatePreferences {
    fun target(
        suggestion: Suggestion,
        textBeforeCursor: String,
        languageTag: String,
    ): CorrectionCandidatePreference? {
        if (suggestion.kind != SuggestionKind.CORRECTION) return null
        val replaceCount = suggestion.replaceBeforeCursor
        if (replaceCount <= 0 || replaceCount > textBeforeCursor.length) return null
        val typed = textBeforeCursor.takeLast(replaceCount)
        if (typed.isBlank()) return null
        return CorrectionCandidatePreference(
            typedText = typed,
            suggestedText = suggestion.text,
            languageTag = languageTag,
        )
    }
}
