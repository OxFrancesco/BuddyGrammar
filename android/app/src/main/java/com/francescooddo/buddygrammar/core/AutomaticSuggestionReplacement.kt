package com.francescooddo.buddygrammar.core

enum class AutomaticSuggestionSource(val receiptValue: String) {
    TAP_LATTICE("tapLattice"),
    SPELLING("spelling"),
    SHORTCUT("shortcut"),
    SWIPE("swipe"),
}

/**
 * Immutable metadata captured with a rendered replacement suggestion.
 *
 * Requiring the exact bounded editor observation before deletion prevents a
 * stale strip candidate from replacing an unrelated suffix with the same
 * UTF-16 length.
 */
@ConsistentCopyVisibility
data class AutomaticSuggestionReplacement private constructor(
    val originalText: String,
    val replacementText: String,
    val boundaryText: String,
    val precedingContext: String,
    val source: AutomaticSuggestionSource,
    val renderedFieldEpoch: Long? = null,
    val renderedFieldIdentifier: String? = null,
    val renderedLanguageTag: String? = null,
) {
    val expectedContextBeforeCursor: String get() = precedingContext + originalText
    val insertion: String get() = replacementText + boundaryText

    fun matches(
        contextBeforeCursor: String,
        replaceBeforeCursor: Int,
        insertion: String,
    ): Boolean =
        contextBeforeCursor == expectedContextBeforeCursor &&
            replaceBeforeCursor == originalText.length &&
            insertion == this.insertion

    /** Adds the editor ownership captured when this candidate enters the UI. */
    fun ownedBy(
        fieldEpoch: Long,
        fieldIdentifier: String,
        languageTag: String,
    ): AutomaticSuggestionReplacement {
        require(fieldIdentifier.isNotBlank()) { "fieldIdentifier must not be blank" }
        require(languageTag.isNotBlank()) { "languageTag must not be blank" }
        return copy(
            renderedFieldEpoch = fieldEpoch,
            renderedFieldIdentifier = fieldIdentifier,
            renderedLanguageTag = languageTag,
        )
    }

    fun isOwnedBy(
        fieldEpoch: Long,
        fieldIdentifier: String,
        languageTag: String,
    ): Boolean = renderedFieldEpoch == fieldEpoch &&
        renderedFieldIdentifier == fieldIdentifier &&
        renderedLanguageTag == languageTag

    companion object {
        fun create(
            originalText: String,
            replacementText: String,
            boundaryText: String,
            precedingContext: String,
            source: AutomaticSuggestionSource,
        ): AutomaticSuggestionReplacement? {
            if (
                originalText.isEmpty() || replacementText.isEmpty() ||
                originalText == replacementText
            ) return null
            return AutomaticSuggestionReplacement(
                originalText = originalText,
                replacementText = replacementText,
                boundaryText = boundaryText,
                precedingContext = precedingContext,
                source = source,
            )
        }
    }
}
