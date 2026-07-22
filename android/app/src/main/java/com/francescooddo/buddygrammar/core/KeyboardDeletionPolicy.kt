package com.francescooddo.buddygrammar.core

/** Grapheme-safe word-delete boundary expressed in InputConnection UTF-16 units. */
internal class KeyboardDeletionPolicy(
    private val boundaryProvider: GraphemeBoundaryProvider,
) {
    fun utf16UnitsBeforeCursor(
        textBeforeCursor: String,
        leadingEdgeMayBeTruncated: Boolean,
    ): Int? {
        if (textBeforeCursor.isEmpty()) return 0
        val boundaries = boundaryProvider.validatedBoundaries(textBeforeCursor) ?: return null
        var clusterIndex = boundaries.lastIndex - 1
        val targetKind = clusterKind(
            textBeforeCursor,
            boundaries[clusterIndex],
            boundaries[clusterIndex + 1],
        )
        if (targetKind == ClusterKind.OTHER) {
            val start = boundaries[clusterIndex]
            if (start == 0 && leadingEdgeMayBeTruncated) return null
            return textBeforeCursor.length - start
        }

        while (clusterIndex >= 0 && clusterKind(
                textBeforeCursor,
                boundaries[clusterIndex],
                boundaries[clusterIndex + 1],
            ) == targetKind
        ) clusterIndex -= 1

        val start = boundaries[clusterIndex + 1]
        if (start == 0 && leadingEdgeMayBeTruncated) return null
        return textBeforeCursor.length - start
    }

    private fun clusterKind(text: String, start: Int, end: Int): ClusterKind {
        val codePoints = text.substring(start, end).codePoints().toArray()
        return when {
            codePoints.all { Character.isWhitespace(it) || Character.isSpaceChar(it) } ->
                ClusterKind.WHITESPACE
            codePoints.any { it.isWordCodePoint() } -> ClusterKind.WORD
            else -> ClusterKind.OTHER
        }
    }

    private fun Int.isWordCodePoint(): Boolean =
        Character.isLetterOrDigit(this) || this == APOSTROPHE || this == CURLY_APOSTROPHE

    private enum class ClusterKind { WHITESPACE, WORD, OTHER }

    private companion object {
        const val APOSTROPHE = '\''.code
        const val CURLY_APOSTROPHE = '’'.code
    }
}
