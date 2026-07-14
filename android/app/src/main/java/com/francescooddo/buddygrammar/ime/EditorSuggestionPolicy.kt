package com.francescooddo.buddygrammar.ime

import android.text.InputType

/** Keeps dictionary intelligence out of editor types where replacement is unsafe or unwanted. */
object EditorSuggestionPolicy {
    fun allowsDictionarySuggestions(inputType: Int): Boolean {
        if (inputType and InputType.TYPE_MASK_CLASS != InputType.TYPE_CLASS_TEXT) return false
        if (inputType and InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS != 0) return false
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        return variation !in UNSAFE_TEXT_VARIATIONS
    }

    private val UNSAFE_TEXT_VARIATIONS = setOf(
        InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_URI,
        InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_PERSON_NAME,
        InputType.TYPE_TEXT_VARIATION_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
    )
}
