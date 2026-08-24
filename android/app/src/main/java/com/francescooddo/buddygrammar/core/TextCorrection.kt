package com.francescooddo.buddygrammar.core

data class TextCorrectionCandidate(
    val capturedText: String,
    val requestText: String,
    val leadingWhitespace: String,
    val trailingWhitespace: String,
) {
    fun replacement(correctedText: String): String =
        leadingWhitespace + correctedText + trailingWhitespace

    companion object {
        fun from(capturedText: String): TextCorrectionCandidate? {
            val leadingCount = capturedText.indexOfFirst { !it.isWhitespace() }
                .let { if (it == -1) capturedText.length else it }
            val trailingStart = capturedText.indexOfLast { !it.isWhitespace() } + 1
            if (leadingCount >= trailingStart) return null
            return TextCorrectionCandidate(
                capturedText = capturedText,
                requestText = capturedText.substring(leadingCount, trailingStart),
                leadingWhitespace = capturedText.substring(0, leadingCount),
                trailingWhitespace = capturedText.substring(trailingStart),
            )
        }
    }
}

data class CursorCorrectionCandidate(
    val candidate: TextCorrectionCandidate,
    val textBeforeCursor: String,
    val textAfterCursor: String,
)

data class CorrectionUndoState(
    val originalText: String,
    val replacementText: String,
    val anchorBefore: String,
    val anchorAfter: String,
) {
    fun matches(contextBeforeCursor: String, contextAfterCursor: String): Boolean =
        contextBeforeCursor == anchorBefore + replacementText &&
            contextAfterCursor == anchorAfter
}

internal class TextContextExtractor(
    private val boundaryProvider: GraphemeBoundaryProvider,
) {
    private val terminators = setOf('.', '!', '?', '\n', '…')

    fun precedingSentence(context: String, maximumCharacters: Int = 1_000): TextCorrectionCandidate? {
        if (context.isEmpty() || maximumCharacters <= 0) return null
        val boundedText = boundedSuffix(context, maximumCharacters) ?: return null
        val bounded = boundedText.value
        val contentEnd = bounded.indexOfLast { !it.isWhitespace() } + 1
        if (contentEnd <= 0) return null
        val lastContentIndex = contentEnd - 1
        val searchEnd = if (bounded[lastContentIndex] in terminators) lastContentIndex else contentEnd
        val previousTerminator = bounded.substring(0, searchEnd).indexOfLast { it in terminators }
        val start = if (previousTerminator >= 0) {
            boundedText.boundaryAtOrAfter(previousTerminator + 1) ?: return null
        } else {
            0
        }
        return TextCorrectionCandidate.from(bounded.substring(start))
    }

    fun currentSentence(
        contextBeforeCursor: String,
        contextAfterCursor: String,
        maximumCharacters: Int = 1_000,
    ): CursorCorrectionCandidate? {
        if (maximumCharacters <= 0) return null
        val boundedBefore = boundedSuffix(contextBeforeCursor, maximumCharacters) ?: return null
        val boundedAfter = boundedPrefix(contextAfterCursor, maximumCharacters) ?: return null
        val before = boundedBefore.value
        val after = boundedAfter.value
        val lastContentIndex = before.indexOfLast { !it.isWhitespace() }

        if (lastContentIndex >= 0 && before[lastContentIndex] in terminators) {
            val preceding = precedingSentence(before, maximumCharacters) ?: return null
            return CursorCorrectionCandidate(
                candidate = preceding,
                textBeforeCursor = preceding.capturedText,
                textAfterCursor = "",
            )
        }

        val previousTerminator = before.indexOfLast { it in terminators }
        val leftStart = if (previousTerminator >= 0) {
            boundedBefore.boundaryAtOrAfter(previousTerminator + 1) ?: return null
        } else {
            0
        }
        val left = before.substring(leftStart)
        val nextTerminator = after.indexOfFirst { it in terminators }
        val rightEnd = if (nextTerminator >= 0) {
            boundedAfter.boundaryAtOrAfter(nextTerminator + 1) ?: return null
        } else {
            after.length
        }
        val right = after.substring(0, rightEnd)
        val candidate = TextCorrectionCandidate.from(left + right) ?: return null
        return CursorCorrectionCandidate(
            candidate = candidate,
            textBeforeCursor = left,
            textAfterCursor = right,
        )
    }

    private fun boundedSuffix(text: String, maximumCharacters: Int): BoundedText? {
        if (!text.hasWellFormedUtf16()) return null
        val boundaries = boundaryProvider.validatedBoundaries(text) ?: return null
        val minimumStart = (text.length - maximumCharacters).coerceAtLeast(0)
        val start = boundaries.firstOrNull { it >= minimumStart } ?: return null
        return BoundedText(
            value = text.substring(start),
            boundaries = boundaries
                .asSequence()
                .filter { it >= start }
                .map { it - start }
                .toList()
                .toIntArray(),
        )
    }

    private fun boundedPrefix(text: String, maximumCharacters: Int): BoundedText? {
        if (!text.hasWellFormedUtf16()) return null
        val boundaries = boundaryProvider.validatedBoundaries(text) ?: return null
        val maximumEnd = maximumCharacters.coerceAtMost(text.length)
        val end = boundaries.lastOrNull { it <= maximumEnd } ?: return null
        return BoundedText(
            value = text.substring(0, end),
            boundaries = boundaries.takeWhile { it <= end }.toIntArray(),
        )
    }

    private data class BoundedText(
        val value: String,
        val boundaries: IntArray,
    ) {
        fun boundaryAtOrAfter(offset: Int): Int? = boundaries.firstOrNull { it >= offset }
    }

    private fun String.hasWellFormedUtf16(): Boolean {
        var index = 0
        while (index < length) {
            val codeUnit = this[index]
            when {
                codeUnit.isHighSurrogate() -> {
                    if (index + 1 >= length || !this[index + 1].isLowSurrogate()) return false
                    index += 2
                }
                codeUnit.isLowSurrogate() -> return false
                else -> index += 1
            }
        }
        return true
    }
}

object CorrectionOutputGuard {
    private val disallowedPrefixes = listOf(
        "here is the corrected text",
        "here's the corrected text",
        "corrected text:",
        "the corrected text is",
        "grammar correction:",
        "fixed text:",
        "corrected version:",
        "here is the revised text",
        "here's the revised text",
    )

    fun sanitize(output: String, input: String): String {
        val trimmed = output.trim()
        require(trimmed.isNotEmpty()) { "The correction service returned empty text." }
        val normalized = trimmed.replace('’', '\'').lowercase()
        require(disallowedPrefixes.none(normalized::startsWith)) {
            "The correction service returned an explanation instead of corrected text."
        }
        require(trimmed.length <= maxOf(500, input.length * 4)) {
            "The correction service returned text that was too large to apply safely."
        }
        return trimmed
    }
}
