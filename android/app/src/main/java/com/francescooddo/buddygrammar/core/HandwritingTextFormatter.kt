package com.francescooddo.buddygrammar.core

/**
 * Adapts recognized handwriting to the sentence context at the cursor:
 * normalizes ALL-CAPS recognitions, restores the standalone pronoun "I",
 * capitalizes at a sentence start, and demotes a stray leading capital in
 * the middle of a sentence.
 */
object HandwritingTextFormatter {
    fun textForInsertion(recognizedText: String, contextBeforeCursor: String): String {
        var text = recognizedText

        val letters = text.filter { it.isLetter() }
        val isAllCaps = letters.length > 1 &&
            letters.any { it.isUpperCase() } &&
            letters.none { it.isLowerCase() }
        if (isAllCaps) text = text.lowercase()

        text = text.replace(Regex("\\bi\\b"), "I")

        val firstLetter = text.indexOfFirst { it.isLetter() }
        if (firstLetter == -1) return text

        if (SuggestionEngine.isSentenceStart(contextBeforeCursor)) {
            text = text.replaceRange(
                firstLetter,
                firstLetter + 1,
                text[firstLetter].uppercaseChar().toString(),
            )
        } else if (shouldLowercaseFirstWord(text, firstLetter)) {
            text = text.replaceRange(
                firstLetter,
                firstLetter + 1,
                text[firstLetter].lowercaseChar().toString(),
            )
        }
        return text
    }

    /**
     * Demotes a leading capital in the middle of a sentence, but only for
     * plain Title-case words. "I", acronyms ("NASA"), and mixed-case words
     * ("BuddyGrammar", "iPhone") keep their casing.
     */
    private fun shouldLowercaseFirstWord(text: String, firstLetter: Int): Boolean {
        if (!text[firstLetter].isUpperCase()) return false
        val word = text.substring(firstLetter).takeWhile { it.isLetter() || it == '\'' }
        if (word == "I" || word.startsWith("I'")) return false
        return word.drop(1).none { it.isUpperCase() }
    }
}
