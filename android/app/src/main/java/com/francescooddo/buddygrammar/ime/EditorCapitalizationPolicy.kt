package com.francescooddo.buddygrammar.ime

import android.text.InputType
import android.text.TextUtils
import com.francescooddo.buddygrammar.core.SuggestionEngine

enum class EditorCapitalizationMode {
    NONE,
    SENTENCES,
    WORDS,
    CHARACTERS,
    ;

    fun shouldShift(textBeforeCursor: String): Boolean = when (this) {
        NONE -> false
        SENTENCES -> SuggestionEngine.isSentenceStart(textBeforeCursor)
        WORDS -> textBeforeCursor.lastOrNull()?.isWordCharacter() != true
        CHARACTERS -> true
    }

    val cursorCapsModeRequest: Int
        get() = when (this) {
            NONE -> 0
            SENTENCES -> TextUtils.CAP_MODE_SENTENCES
            WORDS -> TextUtils.CAP_MODE_WORDS
            CHARACTERS -> TextUtils.CAP_MODE_CHARACTERS
        }

    private fun Char.isWordCharacter(): Boolean = isLetterOrDigit() || this == '\''
}

/** Maps Android's editor-declared capitalization traits into keyboard state. */
object EditorCapitalizationPolicy {
    fun mode(inputType: Int, fieldKind: EditorFieldKind): EditorCapitalizationMode {
        if (inputType and InputType.TYPE_MASK_CLASS != InputType.TYPE_CLASS_TEXT) {
            return EditorCapitalizationMode.NONE
        }
        if (fieldKind in NEVER_AUTO_CAPITALIZE) return EditorCapitalizationMode.NONE

        return when {
            inputType and InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS != 0 ->
                EditorCapitalizationMode.CHARACTERS
            inputType and InputType.TYPE_TEXT_FLAG_CAP_WORDS != 0 ->
                EditorCapitalizationMode.WORDS
            inputType and InputType.TYPE_TEXT_FLAG_CAP_SENTENCES != 0 ->
                EditorCapitalizationMode.SENTENCES
            else -> EditorCapitalizationMode.NONE
        }
    }

    private val NEVER_AUTO_CAPITALIZE = setOf(
        EditorFieldKind.EMAIL,
        EditorFieldKind.URL,
        EditorFieldKind.CODE,
        EditorFieldKind.PASSWORD,
        EditorFieldKind.ONE_TIME_CODE,
    )
}
