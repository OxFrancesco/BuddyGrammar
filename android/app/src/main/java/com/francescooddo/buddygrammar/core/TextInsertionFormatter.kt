package com.francescooddo.buddygrammar.core

/** Spacing rules shared by typed punctuation, handwriting, and dictation. */
object TextInsertionFormatter {
    data class InsertionPlan(val text: String, val deleteBeforeCursor: Int)

    fun planInsertion(text: String, contextBeforeCursor: String?): InsertionPlan {
        // Unknown context means literal insertion: infer neither spacing nor deletion.
        if (contextBeforeCursor == null) return InsertionPlan(text, deleteBeforeCursor = 0)
        val deleteCount = whitespaceToDeleteBefore(contextBeforeCursor, text)
        val contextAfterDeletion = contextBeforeCursor.dropLast(deleteCount)
        return InsertionPlan(
            text = textForInsertion(text, contextAfterDeletion),
            deleteBeforeCursor = deleteCount,
        )
    }

    fun textForInsertion(text: String, contextBeforeCursor: String): String {
        if (text.isEmpty() || contextBeforeCursor.isEmpty()) return text
        val previous = contextBeforeCursor.last()
        val first = text.first()
        val needsSpace = !previous.isWhitespace() &&
            previous !in OPENING_CHARACTERS &&
            first !in CLOSING_PUNCTUATION &&
            !first.isWhitespace()
        return if (needsSpace) " $text" else text
    }

    fun whitespaceToDeleteBefore(contextBeforeCursor: String, insertion: String): Int {
        val first = insertion.firstOrNull() ?: return 0
        if (first !in CLOSING_PUNCTUATION) return 0
        return contextBeforeCursor.takeLastWhile { it == ' ' || it == '\t' }.length
    }

    private val OPENING_CHARACTERS = setOf('(', '[', '{', '<', '/', '@', '#', '\'', '’', '-', '–', '—')
    private val CLOSING_PUNCTUATION = setOf('.', ',', '!', '?', ';', ':', '%', ')', ']', '}', '>', '…')
}
