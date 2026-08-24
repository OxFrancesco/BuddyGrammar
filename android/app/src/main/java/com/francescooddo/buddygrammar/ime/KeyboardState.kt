package com.francescooddo.buddygrammar.ime

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

enum class KeyboardLayer {
    LETTERS,
    NUMBERS,
    SYMBOLS,
    LATEX,
    EMOJI,
    HANDWRITING,
    VOICE,
}

data class KeyboardRefreshPlan(
    val shouldReadContext: Boolean,
    val shouldQueryCursorCapsMode: Boolean,
    val shouldShowSuggestions: Boolean,
) {
    fun shouldUseCursorCapsMode(contextReadSucceeded: Boolean): Boolean =
        shouldQueryCursorCapsMode || !contextReadSucceeded
}

object KeyboardRefreshPolicy {
    fun plan(
        suggestionsAllowed: Boolean,
        readContextAllowed: Boolean,
        practiceActive: Boolean,
    ): KeyboardRefreshPlan {
        val shouldReadContext = suggestionsAllowed && readContextAllowed
        return KeyboardRefreshPlan(
            shouldReadContext = shouldReadContext,
            shouldQueryCursorCapsMode = !shouldReadContext,
            shouldShowSuggestions = shouldReadContext && !practiceActive,
        )
    }
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
        val doubleTap = lastShiftTapMillis != Long.MIN_VALUE &&
            now - lastShiftTapMillis in 0..DOUBLE_TAP_WINDOW_MS
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

    /** Applies the active editor's declared capitalization behavior. */
    fun updateAutoShift(
        textBeforeCursor: String?,
        mode: EditorCapitalizationMode,
    ) {
        // Unknown InputConnection context is not equivalent to document start.
        if (textBeforeCursor == null) return
        if (!capsLock) shift = mode.shouldShift(textBeforeCursor)
    }

    /** Applies the editor's privacy-preserving capitalization signal. */
    fun updateAutoShiftFromCursorCapsMode(cursorCapsMode: Int?) {
        // A missing editor signal is unknown, not a request to capitalize.
        if (cursorCapsMode == null) return
        if (!capsLock) shift = cursorCapsMode != 0
    }

    /** Resets the state for a new input field. */
    fun configureForNewInput(
        startOnNumbers: Boolean,
        autoCapitalize: Boolean = !startOnNumbers,
    ) {
        layer = if (startOnNumbers) KeyboardLayer.NUMBERS else KeyboardLayer.LETTERS
        capsLock = false
        shift = !startOnNumbers && autoCapitalize
        lastShiftTapMillis = Long.MIN_VALUE
    }

    companion object {
        const val DOUBLE_TAP_WINDOW_MS = 350L
    }
}
