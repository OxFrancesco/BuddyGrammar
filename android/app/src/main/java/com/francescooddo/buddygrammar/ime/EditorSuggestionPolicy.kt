package com.francescooddo.buddygrammar.ime

/** Compatibility wrapper; new callers consume the complete evaluated capability object. */
object EditorSuggestionPolicy {
    fun allowsDictionarySuggestions(inputType: Int): Boolean = EditorCapabilityPolicy
        .evaluateAndroid(
            inputType = inputType,
            imeOptions = 0,
            cloudConsentGranted = false,
        )
        .suggestions
        .isAllowed
}
