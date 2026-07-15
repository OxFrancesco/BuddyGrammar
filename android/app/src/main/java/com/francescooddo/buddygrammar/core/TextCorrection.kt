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

object TextContextExtractor {
    private val terminators = setOf('.', '!', '?', '\n', '…')

    fun precedingSentence(context: String, maximumCharacters: Int = 1_000): TextCorrectionCandidate? {
        if (context.isEmpty() || maximumCharacters <= 0) return null
        val bounded = context.takeLast(maximumCharacters)
        val contentEnd = bounded.indexOfLast { !it.isWhitespace() } + 1
        if (contentEnd <= 0) return null
        val lastContentIndex = contentEnd - 1
        val searchEnd = if (bounded[lastContentIndex] in terminators) lastContentIndex else contentEnd
        val previousTerminator = bounded.substring(0, searchEnd).indexOfLast { it in terminators }
        val start = if (previousTerminator >= 0) previousTerminator + 1 else 0
        return TextCorrectionCandidate.from(bounded.substring(start))
    }

    fun currentSentence(
        contextBeforeCursor: String,
        contextAfterCursor: String,
        maximumCharacters: Int = 1_000,
    ): CursorCorrectionCandidate? {
        if (maximumCharacters <= 0) return null
        val before = contextBeforeCursor.takeLast(maximumCharacters)
        val after = contextAfterCursor.take(maximumCharacters)
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
        val left = before.substring(if (previousTerminator >= 0) previousTerminator + 1 else 0)
        val nextTerminator = after.indexOfFirst { it in terminators }
        val right = after.substring(0, if (nextTerminator >= 0) nextTerminator + 1 else after.length)
        val candidate = TextCorrectionCandidate.from(left + right) ?: return null
        return CursorCorrectionCandidate(
            candidate = candidate,
            textBeforeCursor = left,
            textAfterCursor = right,
        )
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
