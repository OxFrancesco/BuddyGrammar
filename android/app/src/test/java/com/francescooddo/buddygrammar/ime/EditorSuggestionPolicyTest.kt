package com.francescooddo.buddygrammar.ime

import android.text.InputType
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorSuggestionPolicyTest {
    @Test
    fun `allows dictionary suggestions only in safe text fields`() {
        assertTrue(EditorSuggestionPolicy.allowsDictionarySuggestions(InputType.TYPE_CLASS_TEXT))
        assertFalse(
            EditorSuggestionPolicy.allowsDictionarySuggestions(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS,
            ),
        )
        assertFalse(
            EditorSuggestionPolicy.allowsDictionarySuggestions(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
            ),
        )
        assertFalse(
            EditorSuggestionPolicy.allowsDictionarySuggestions(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI,
            ),
        )
        assertFalse(
            EditorSuggestionPolicy.allowsDictionarySuggestions(
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PERSON_NAME,
            ),
        )
        assertFalse(
            EditorSuggestionPolicy.allowsDictionarySuggestions(InputType.TYPE_CLASS_NUMBER),
        )
    }
}
