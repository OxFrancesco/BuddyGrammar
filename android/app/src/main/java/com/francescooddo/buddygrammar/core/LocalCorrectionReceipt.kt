package com.francescooddo.buddygrammar.core

/**
 * Memory-only evidence for one automatic word replacement. It contains just
 * enough anchored text to make an immediate revert safe and is never encoded.
 */
class LocalCorrectionReceipt private constructor(
    val originalText: String,
    val replacementText: String,
    val boundaryText: String,
    val anchorBefore: String,
    val contextWords: List<String>,
    val languageTag: String,
) {
    val appliedText: String get() = replacementText + boundaryText
    val acceptance: LocalCorrectionAcceptance
        get() = LocalCorrectionAcceptance(replacementText, contextWords, languageTag)

    fun revertPlan(
        contextBeforeCursor: String,
        mode: LocalCorrectionRevertMode = LocalCorrectionRevertMode.BACKSPACE,
    ): LocalCorrectionRevert? {
        val expectedSuffix = anchorBefore + appliedText
        if (!contextBeforeCursor.endsWith(expectedSuffix)) return null
        return LocalCorrectionRevert(
            deleteBeforeCursor = appliedText.length,
            insertText = when (mode) {
                LocalCorrectionRevertMode.BACKSPACE -> originalText
                LocalCorrectionRevertMode.VISIBLE_UNDO -> originalText + boundaryText
            },
            rejection = LocalCorrectionRejection(
                rejectedWord = replacementText,
                contextWords = contextWords,
                languageTag = languageTag,
            ),
        )
    }

    companion object {
        fun create(
            originalText: String,
            replacementText: String,
            contextBeforeOriginal: String,
            boundaryText: String,
            languageTag: String,
        ): LocalCorrectionReceipt {
            require(originalText.isNotEmpty()) { "Original correction text must not be empty." }
            require(replacementText.isNotEmpty()) { "Replacement correction text must not be empty." }
            require(originalText != replacementText) { "A correction must change the text." }
            return LocalCorrectionReceipt(
                originalText = originalText,
                replacementText = replacementText,
                boundaryText = boundaryText,
                anchorBefore = contextBeforeOriginal.takeLast(ANCHOR_LENGTH),
                contextWords = contextWords(contextBeforeOriginal),
                languageTag = languageTag,
            )
        }

        private fun contextWords(text: String): List<String> {
            val sentenceStart = text.indexOfLast { it in SENTENCE_TERMINATORS }
            return WORD_PATTERN
                .findAll(text.substring(sentenceStart + 1))
                .map { it.value }
                .toList()
                .takeLast(2)
        }

        private const val ANCHOR_LENGTH = 32
        private val SENTENCE_TERMINATORS = setOf('.', '!', '?', '\n', '…')
        private val WORD_PATTERN = Regex("[\\p{L}\\p{N}]+(?:'[\\p{L}\\p{N}]+)*")
    }
}

enum class LocalCorrectionRevertMode {
    BACKSPACE,
    VISIBLE_UNDO,
}

data class LocalCorrectionRevert(
    val deleteBeforeCursor: Int,
    val insertText: String,
    val rejection: LocalCorrectionRejection,
)

data class LocalCorrectionRejection(
    val rejectedWord: String,
    val contextWords: List<String>,
    val languageTag: String,
) {
    fun recordIn(personalModel: PersonalLanguageModel) {
        personalModel.reject(
            contextWords = contextWords,
            word = rejectedWord,
            languageTag = languageTag,
        )
    }
}

data class LocalCorrectionAcceptance(
    val acceptedWord: String,
    val contextWords: List<String>,
    val languageTag: String,
) {
    fun recordIn(personalModel: PersonalLanguageModel) {
        personalModel.learn(
            contextWords = contextWords,
            word = acceptedWord,
            languageTag = languageTag,
        )
    }
}
