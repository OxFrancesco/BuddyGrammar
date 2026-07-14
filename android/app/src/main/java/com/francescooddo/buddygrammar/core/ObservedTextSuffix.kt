package com.francescooddo.buddygrammar.core

/**
 * Remembers a bounded editor suffix after already-learned recognized text.
 * The next unchanged word boundary consumes it instead of learning or
 * auto-correcting the final word a second time.
 */
class ObservedTextSuffix(private val maximumCharacters: Int = 64) {
    private var suffix: String? = null

    init {
        require(maximumCharacters > 0) { "maximumCharacters must be positive" }
    }

    fun observe(committedText: String, contextBeforeCursor: String) {
        suffix = if (
            committedText.lastOrNull()?.isLetterOrDigit() == true &&
            contextBeforeCursor.isNotEmpty()
        ) {
            contextBeforeCursor.takeLast(maximumCharacters)
        } else {
            null
        }
    }

    fun consumeIfUnchanged(contextBeforeCursor: String): Boolean {
        val expected = suffix
        suffix = null
        return expected != null && contextBeforeCursor.endsWith(expected)
    }

    fun retainIfUnchanged(contextBeforeCursor: String) {
        val expected = suffix ?: return
        if (!contextBeforeCursor.endsWith(expected)) suffix = null
    }

    fun clear() {
        suffix = null
    }
}
