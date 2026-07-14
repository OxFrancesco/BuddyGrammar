package com.francescooddo.buddygrammar.ime

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.francescooddo.buddygrammar.core.SuggestionEngine

enum class KeyboardLayer {
    LETTERS,
    NUMBERS,
    SYMBOLS,
    LATEX,
    EMOJI,
    HANDWRITING,
    VOICE,
}

/**
 * Plain Kotlin state holder for the keyboard so layer and shift logic stays
 * testable outside of the InputMethodService.
 */
class KeyboardState(private val nowMillis: () -> Long = System::currentTimeMillis) {
    var layer by mutableStateOf(KeyboardLayer.LETTERS)
        private set
    var shift by mutableStateOf(true)
        private set
    var capsLock by mutableStateOf(false)
        private set

    private var lastShiftTapMillis = Long.MIN_VALUE

    val uppercase: Boolean
        get() = shift || capsLock

    fun switchLayer(target: KeyboardLayer) {
        layer = target
    }

    /** Single tap toggles shift; a quick double tap enables caps lock. */
    fun onShiftTapped() {
        val now = nowMillis()
        val doubleTap = now - lastShiftTapMillis <= DOUBLE_TAP_WINDOW_MS
        lastShiftTapMillis = now
        when {
            capsLock -> {
                capsLock = false
                shift = false
            }
            doubleTap -> {
                capsLock = true
                shift = false
            }
            else -> shift = !shift
        }
    }

    /** Called after a character is committed so one-shot shift releases. */
    fun onCharacterCommitted() {
        if (!capsLock) shift = false
    }

    /** Auto-enables shift at the start of a sentence (unless caps lock is on). */
    fun updateAutoShift(textBeforeCursor: String) {
        if (!capsLock) shift = SuggestionEngine.isSentenceStart(textBeforeCursor)
    }

    /** Resets the state for a new input field. */
    fun configureForNewInput(startOnNumbers: Boolean) {
        layer = if (startOnNumbers) KeyboardLayer.NUMBERS else KeyboardLayer.LETTERS
        capsLock = false
        shift = !startOnNumbers
        lastShiftTapMillis = Long.MIN_VALUE
    }

    companion object {
        const val DOUBLE_TAP_WINDOW_MS = 350L
    }
}
