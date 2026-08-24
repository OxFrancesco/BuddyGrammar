package com.francescooddo.buddygrammar.core

import android.icu.text.BreakIterator
import java.util.Locale

/** Supplies extended-grapheme boundaries as UTF-16 offsets into [text]. */
internal fun interface GraphemeBoundaryProvider {
    fun boundaries(text: String): IntArray
}

/** Android's ICU implementation of Unicode extended-grapheme segmentation. */
internal object AndroidIcuGraphemeBoundaryProvider : GraphemeBoundaryProvider {
    override fun boundaries(text: String): IntArray {
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
        iterator.setText(text)
        return buildList {
            var boundary = iterator.first()
            while (boundary != BreakIterator.DONE) {
                add(boundary)
                boundary = iterator.next()
            }
        }.toIntArray()
    }
}

internal fun GraphemeBoundaryProvider.validatedBoundaries(text: String): IntArray? {
    val boundaries = runCatching { boundaries(text) }.getOrNull() ?: return null
    if (boundaries.isEmpty() || boundaries.first() != 0 || boundaries.last() != text.length) {
        return null
    }
    if (boundaries.asSequence().zipWithNext().any { (left, right) -> left >= right }) return null
    return boundaries
}

/**
 * Resolves grapheme movement into the UTF-16 units expected by [android.view.inputmethod.InputConnection].
 *
 * The boundary provider is injected so offset policy remains a pure JVM-testable seam while production
 * uses Android ICU. A boundary at a possibly truncated context edge is rejected: the caller can then use
 * its deterministic editor-key fallback instead of risking half of an extended grapheme cluster.
 */
internal class GraphemeClusterOffsets(
    private val boundaryProvider: GraphemeBoundaryProvider,
) {
    fun utf16UnitsBeforeCursor(
        textBeforeCursor: String,
        graphemeCount: Int,
        leadingEdgeMayBeTruncated: Boolean,
    ): Int? {
        if (graphemeCount <= 0 || textBeforeCursor.isEmpty()) return 0
        val boundaries = boundaryProvider.validatedBoundaries(textBeforeCursor) ?: return null
        val targetIndex = (boundaries.lastIndex - graphemeCount).coerceAtLeast(0)
        val target = boundaries[targetIndex]
        if (target == 0 && leadingEdgeMayBeTruncated) return null
        return textBeforeCursor.length - target
    }

    fun utf16UnitsAfterCursor(
        textAfterCursor: String,
        graphemeCount: Int,
        trailingEdgeMayBeTruncated: Boolean,
    ): Int? {
        if (graphemeCount <= 0 || textAfterCursor.isEmpty()) return 0
        val boundaries = boundaryProvider.validatedBoundaries(textAfterCursor) ?: return null
        val target = boundaries[graphemeCount.coerceAtMost(boundaries.lastIndex)]
        if (target == textAfterCursor.length && trailingEdgeMayBeTruncated) return null
        return target
    }
}
