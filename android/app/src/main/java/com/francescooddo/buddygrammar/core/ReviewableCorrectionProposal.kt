package com.francescooddo.buddygrammar.core

import java.util.UUID

enum class BuddyRewriteIntent(val title: String) {
    FIX("Fix"),
    SHORTEN("Shorten"),
    CLEARER("Clearer"),
    FRIENDLY("Friendly"),
    FORMAL("Formal");

    fun instruction(base: String): String {
        val transformation = when (this) {
            FIX -> "Fix only clear grammar, spelling, punctuation, and capitalization errors."
            SHORTEN -> "Make the text meaningfully shorter without removing important information."
            CLEARER -> "Improve clarity and directness while preserving the meaning and factual claims."
            FRIENDLY -> "Use a warm, friendly tone while preserving the meaning and factual claims."
            FORMAL -> "Use a polished, professional tone while preserving the meaning and factual claims."
        }
        return "${base.trim()}\n$transformation Return only the replacement text."
    }
}

data class ReviewableCorrectionProposal(
    val intent: BuddyRewriteIntent,
    val originalText: String,
    val proposedText: String,
    val id: UUID = UUID.randomUUID(),
) {
    val change = BoundedTextChange(originalText, proposedText)
    val hasChanges: Boolean get() = originalText != proposedText
}

data class BoundedTextChange(
    val commonPrefix: String,
    val originalChangedText: String,
    val proposedChangedText: String,
    val commonSuffix: String,
) {
    private constructor(values: Values) : this(
        values.commonPrefix,
        values.originalChangedText,
        values.proposedChangedText,
        values.commonSuffix,
    )

    constructor(original: String, proposed: String) : this(values(original, proposed))

    private data class Values(
        val commonPrefix: String,
        val originalChangedText: String,
        val proposedChangedText: String,
        val commonSuffix: String,
    )

    companion object {
        private fun values(original: String, proposed: String): Values {
            if (original == proposed) return Values(original, "", "", "")
            // Kotlin String indices address UTF-16 code units. Diffing those
            // directly can cut emoji, combining marks, or a ZWJ sequence into
            // invalid review spans. Work in user-perceived characters.
            val originalGraphemes = original.userPerceivedCharacters()
            val proposedGraphemes = proposed.userPerceivedCharacters()
            var prefix = 0
            while (
                prefix < minOf(originalGraphemes.size, proposedGraphemes.size) &&
                originalGraphemes[prefix] == proposedGraphemes[prefix]
            ) {
                prefix += 1
            }
            var suffix = 0
            while (
                suffix < originalGraphemes.size - prefix &&
                suffix < proposedGraphemes.size - prefix &&
                originalGraphemes[originalGraphemes.size - suffix - 1] ==
                proposedGraphemes[proposedGraphemes.size - suffix - 1]
            ) {
                suffix += 1
            }
            return Values(
                commonPrefix = originalGraphemes.subList(0, prefix).joinToString(""),
                originalChangedText = originalGraphemes
                    .subList(prefix, originalGraphemes.size - suffix)
                    .joinToString(""),
                proposedChangedText = proposedGraphemes
                    .subList(prefix, proposedGraphemes.size - suffix)
                    .joinToString(""),
                commonSuffix = originalGraphemes
                    .subList(originalGraphemes.size - suffix, originalGraphemes.size)
                    .joinToString(""),
            )
        }

    }
}

/** Android/JVM grapheme segmentation shared by diffing and bounded previews. */
internal fun String.userPerceivedCharacters(): List<String> {
    val boundaries = AndroidIcuGraphemeBoundaryProvider.validatedBoundaries(this)
    if (boundaries != null) {
        return boundaries.asSequence()
            .zipWithNext()
            .map { (start, end) -> substring(start, end) }
            .toList()
    }

    // Local JVM tests do not provide Android ICU. Java 17's \X implements
    // extended grapheme clusters, including emoji ZWJ and combining sequences.
    return runCatching {
        Regex("\\X").findAll(this).map { match -> match.value }.toList()
    }.getOrElse {
        // Last-resort validity fallback for an unusual regex runtime. It may
        // be less semantically rich, but never separates a surrogate pair.
        buildList {
            var start = 0
            while (start < length) {
                val end = start + Character.charCount(codePointAt(start))
                add(substring(start, end))
                start = end
            }
        }
    }
}
