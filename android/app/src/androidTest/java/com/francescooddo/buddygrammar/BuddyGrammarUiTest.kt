package com.francescooddo.buddygrammar

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.francescooddo.buddygrammar.ui.BuddyGrammarApp
import com.francescooddo.buddygrammar.ui.BuddyGrammarAppState
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class BuddyGrammarUiTest {
    @get:Rule
    val composeRule = createComposeRule()

    private lateinit var state: BuddyGrammarAppState

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("buddygrammar_shared", android.content.Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        state = BuddyGrammarAppState(context)
        composeRule.setContent {
            BuddyGrammarApp(
                state = state,
                onRecord = {},
                onOpenKeyboardSettings = {},
                onShowKeyboardPicker = {},
            )
        }
    }

    @After
    fun tearDown() {
        state.close()
    }

    @Test
    fun onboardingRequiresConsentAndReachesKeyboardSetup() {
        composeRule.onNodeWithText("Write with a little magic").assertIsDisplayed()
        composeRule.onNodeWithText("Continue").performClick()
        composeRule.onNodeWithText("A smarter keyboard everywhere").assertIsDisplayed()
        composeRule.onNodeWithText("Continue").performClick()
        composeRule.onNodeWithText("Your words stay yours").assertIsDisplayed()
        composeRule.onNode(isToggleable()).performClick()
        composeRule.onNodeWithText("Get started").performClick()
        composeRule.onNodeWithText("Keyboard setup").assertIsDisplayed()
    }
}
