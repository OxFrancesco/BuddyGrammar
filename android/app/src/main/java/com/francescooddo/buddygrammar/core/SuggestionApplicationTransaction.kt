package com.francescooddo.buddygrammar.core

enum class SuggestionTargetProof {
    INSERT_ONLY,
    PRECEDING_WORD_BOUNDARY,
    KEYBOARD_OWNED_SUFFIX,
}

/** Proves that a bounded editor window contains the full destructive target. */
object SuggestionTargetBoundaryPolicy {
    fun proof(
        contextBeforeCursor: String,
        replaceBeforeCursor: Int,
        keyboardOwnedSuffix: String? = null,
    ): SuggestionTargetProof? {
        if (replaceBeforeCursor < 0 || replaceBeforeCursor > contextBeforeCursor.length) {
            return null
        }
        val targetStart = contextBeforeCursor.length - replaceBeforeCursor
        if (!isCodePointBoundary(contextBeforeCursor, targetStart)) return null
        return when {
            replaceBeforeCursor == 0 -> SuggestionTargetProof.INSERT_ONLY
            keyboardOwnedSuffix.provesTarget(
                contextBeforeCursor = contextBeforeCursor,
                replaceBeforeCursor = replaceBeforeCursor,
            ) -> SuggestionTargetProof.KEYBOARD_OWNED_SUFFIX
            hasPrecedingWordBoundary(contextBeforeCursor, targetStart) ->
                SuggestionTargetProof.PRECEDING_WORD_BOUNDARY
            else -> null
        }
    }

    private fun String?.provesTarget(
        contextBeforeCursor: String,
        replaceBeforeCursor: Int,
    ): Boolean =
        !isNullOrEmpty() &&
            length >= replaceBeforeCursor &&
            contextBeforeCursor.endsWith(this) &&
            isCodePointBoundary(this, length - replaceBeforeCursor)

    private fun hasPrecedingWordBoundary(text: String, targetStart: Int): Boolean {
        if (targetStart <= 0) return false
        val precedingCodePoint = Character.codePointBefore(text, targetStart)
        return !isWordCodePoint(precedingCodePoint)
    }

    private fun isCodePointBoundary(text: String, index: Int): Boolean {
        if (index !in 0..text.length) return false
        if (index == 0 || index == text.length) return true
        return !(text[index - 1].isHighSurrogate() && text[index].isLowSurrogate())
    }

    private fun isWordCodePoint(codePoint: Int): Boolean =
        Character.isLetterOrDigit(codePoint) ||
            codePoint in APOSTROPHE_CODE_POINTS ||
            Character.getType(codePoint) in COMBINING_MARK_TYPES

    private val APOSTROPHE_CODE_POINTS = setOf(
        '\''.code,
        '‘'.code,
        '’'.code,
        'ʼ'.code,
        '＇'.code,
    )
    private val COMBINING_MARK_TYPES = setOf(
        Character.NON_SPACING_MARK.toInt(),
        Character.COMBINING_SPACING_MARK.toInt(),
        Character.ENCLOSING_MARK.toInt(),
    )
}

/** Provenance for a tap composition whose returned editor window may be truncated. */
object KeyboardOwnedWordProvenancePolicy {
    fun startedAtProvenBoundary(
        contextBeforeFirstTap: String?,
        selectionStart: Int,
    ): Boolean {
        if (selectionStart == 0) return true
        val context = contextBeforeFirstTap ?: return false
        if (context.isEmpty()) return false
        val precedingCodePoint = Character.codePointBefore(context, context.length)
        return !isWordCodePoint(precedingCodePoint)
    }

    fun ownsCurrentWord(
        rawCurrentWord: String,
        resolvedTapPath: String,
        startedAtProvenBoundary: Boolean,
    ): Boolean =
        startedAtProvenBoundary &&
            rawCurrentWord.isNotEmpty() &&
            rawCurrentWord.equals(resolvedTapPath, ignoreCase = true)

    private fun isWordCodePoint(codePoint: Int): Boolean =
        Character.isLetterOrDigit(codePoint) ||
            codePoint in APOSTROPHE_CODE_POINTS ||
            Character.getType(codePoint) in COMBINING_MARK_TYPES

    private val APOSTROPHE_CODE_POINTS = setOf(
        '\''.code,
        '‘'.code,
        '’'.code,
        'ʼ'.code,
        '＇'.code,
    )
    private val COMBINING_MARK_TYPES = setOf(
        Character.NON_SPACING_MARK.toInt(),
        Character.COMBINING_SPACING_MARK.toInt(),
        Character.ENCLOSING_MARK.toInt(),
    )
}

/** Immutable capability-independent receipt attached only when a suggestion enters the UI. */
@ConsistentCopyVisibility
data class SuggestionRenderReceipt private constructor(
    val expectedContextBeforeCursor: String,
    val maximumContextLength: Int,
    val fieldEpoch: Long,
    val fieldIdentifier: String,
    val languageTag: String,
    val replaceBeforeCursor: Int,
    val insertion: String,
    val targetProof: SuggestionTargetProof,
) {
    val precedingContext: String
        get() = expectedContextBeforeCursor.dropLast(replaceBeforeCursor)

    fun ownsAndDescribes(
        suggestion: Suggestion,
        currentFieldEpoch: Long,
        currentFieldIdentifier: String,
        currentLanguageTag: String,
    ): Boolean =
        fieldEpoch == currentFieldEpoch &&
            fieldIdentifier == currentFieldIdentifier &&
            languageTag == currentLanguageTag &&
            replaceBeforeCursor == suggestion.replaceBeforeCursor &&
            insertion == suggestion.insertion

    fun matches(
        suggestion: Suggestion,
        contextBeforeCursor: String,
        currentFieldEpoch: Long,
        currentFieldIdentifier: String,
        currentLanguageTag: String,
    ): Boolean = ownsAndDescribes(
        suggestion = suggestion,
        currentFieldEpoch = currentFieldEpoch,
        currentFieldIdentifier = currentFieldIdentifier,
        currentLanguageTag = currentLanguageTag,
    ) && contextBeforeCursor == expectedContextBeforeCursor

    companion object {
        /**
         * Captures one bounded InputConnection observation. A destructive row is omitted when
         * the returned leading edge could hide the beginning of its target.
         */
        fun capture(
            suggestion: Suggestion,
            contextBeforeCursor: String,
            maximumContextLength: Int,
            fieldEpoch: Long,
            fieldIdentifier: String,
            languageTag: String,
            keyboardOwnedSuffix: String? = null,
        ): SuggestionRenderReceipt? {
            if (
                maximumContextLength <= 0 || contextBeforeCursor.length > maximumContextLength ||
                fieldIdentifier.isBlank() || languageTag.isBlank() ||
                suggestion.text.isEmpty() || suggestion.replaceBeforeCursor < 0 ||
                suggestion.replaceBeforeCursor > contextBeforeCursor.length
            ) return null

            val replaceCount = suggestion.replaceBeforeCursor
            val proof = SuggestionTargetBoundaryPolicy.proof(
                contextBeforeCursor = contextBeforeCursor,
                replaceBeforeCursor = replaceCount,
                keyboardOwnedSuffix = keyboardOwnedSuffix,
            ) ?: return null
            return SuggestionRenderReceipt(
                expectedContextBeforeCursor = contextBeforeCursor,
                maximumContextLength = maximumContextLength,
                fieldEpoch = fieldEpoch,
                fieldIdentifier = fieldIdentifier,
                languageTag = languageTag,
                replaceBeforeCursor = replaceCount,
                insertion = suggestion.insertion,
                targetProof = proof,
            )
        }

    }
}

private val Suggestion.insertion: String
    get() = text + if (appendSpace) " " else ""

interface SuggestionApplicationEditor {
    fun beginBatchEdit()
    fun contextBeforeCursor(maximumCharacters: Int): String?
    fun deleteBeforeCursor(characters: Int): Boolean
    fun commitText(text: String): Boolean
    fun endBatchEdit()
}

data class SuggestionCommittedContext(
    val text: String,
    val precedingContext: String,
    val languageTag: String,
)

data class SuggestionApplicationEffect(
    val didMutateEditor: Boolean = false,
)

/** Exact compare-and-swap transaction for non-correction suggestion rows. */
object SuggestionApplicationTransaction {
    fun apply(
        suggestion: Suggestion,
        currentFieldEpoch: Long,
        currentFieldIdentifier: String,
        currentLanguageTag: String,
        editor: SuggestionApplicationEditor,
        onCommitted: (SuggestionCommittedContext) -> Unit = {},
    ): SuggestionApplicationEffect {
        if (suggestion.automaticReplacement != null) return SuggestionApplicationEffect()
        val receipt = suggestion.renderReceipt ?: return SuggestionApplicationEffect()
        if (
            !receipt.ownsAndDescribes(
                suggestion = suggestion,
                currentFieldEpoch = currentFieldEpoch,
                currentFieldIdentifier = currentFieldIdentifier,
                currentLanguageTag = currentLanguageTag,
            )
        ) return SuggestionApplicationEffect()

        var committed = false
        editor.beginBatchEdit()
        try {
            val liveContext = editor.contextBeforeCursor(receipt.maximumContextLength)
                ?: return SuggestionApplicationEffect()
            if (
                !receipt.matches(
                    suggestion = suggestion,
                    contextBeforeCursor = liveContext,
                    currentFieldEpoch = currentFieldEpoch,
                    currentFieldIdentifier = currentFieldIdentifier,
                    currentLanguageTag = currentLanguageTag,
                )
            ) return SuggestionApplicationEffect()

            val replaceCount = receipt.replaceBeforeCursor
            val originalText = liveContext.takeLast(replaceCount)
            if (replaceCount > 0 && !editor.deleteBeforeCursor(replaceCount)) {
                return SuggestionApplicationEffect()
            }
            if (editor.commitText(receipt.insertion)) {
                committed = true
            } else if (replaceCount > 0) {
                editor.commitText(originalText)
            }
        } finally {
            editor.endBatchEdit()
        }

        if (!committed) return SuggestionApplicationEffect()
        onCommitted(
            SuggestionCommittedContext(
                text = suggestion.text.trim(),
                precedingContext = receipt.precedingContext,
                languageTag = receipt.languageTag,
            ),
        )
        return SuggestionApplicationEffect(didMutateEditor = true)
    }
}
