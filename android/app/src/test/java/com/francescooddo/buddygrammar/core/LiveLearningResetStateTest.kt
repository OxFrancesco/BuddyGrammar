package com.francescooddo.buddygrammar.core

import com.francescooddo.buddygrammar.core.adaptive.OutcomeEvidence
import com.francescooddo.buddygrammar.core.adaptive.TapPoint
import com.francescooddo.buddygrammar.core.adaptive.TypingIntelligence
import com.francescooddo.buddygrammar.core.adaptive.TypingOutcome
import com.francescooddo.buddygrammar.core.adaptive.TypingPolicy
import com.francescooddo.buddygrammar.core.adaptive.TypingProfileSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveLearningResetStateTest {
    @Test
    fun `live models cannot retain or resurrect words and calibration after reset`() {
        val state = LiveLearningResetState(LearningResetGenerations())
        val personalOwnerGeneration = state.generations.personalLanguageModel
        val typingOwnerGeneration = state.generations.typingProfile
        var storedWords: String? = null
        var storedTyping: TypingProfileSnapshot? = null
        val oldPersonalModel = PersonalLanguageModel(onPersist = { data ->
            if (state.ownsPersonalLanguageModel(personalOwnerGeneration)) storedWords = data
        })
        val oldTyping = TypingIntelligence()

        oldPersonalModel.learnCommittedText("buddyword", languageTag = "en-US")
        oldPersonalModel.persist()
        oldTyping.observe(calibrationOutcome())
        if (state.ownsTypingProfile(typingOwnerGeneration)) {
            storedTyping = oldTyping.snapshot()
        }
        assertEquals(1, oldPersonalModel.usageCount("buddyword", "en-US"))
        assertEquals(1, storedTyping?.observationCount)

        storedWords = null
        storedTyping = null
        val changes = state.reconcile(
            LearningResetGenerations(
                typingProfile = 1,
                personalLanguageModel = 1,
            ),
        )

        oldPersonalModel.learnCommittedText("buddyword", languageTag = "en-US")
        oldPersonalModel.persist()
        oldTyping.observe(calibrationOutcome())
        if (state.ownsTypingProfile(typingOwnerGeneration)) {
            storedTyping = oldTyping.snapshot()
        }

        assertTrue(changes.typingProfileChanged)
        assertTrue(changes.personalLanguageModelChanged)
        assertFalse(state.ownsTypingProfile(typingOwnerGeneration))
        assertFalse(state.ownsPersonalLanguageModel(personalOwnerGeneration))
        assertNull(storedWords)
        assertNull(storedTyping)
        assertEquals(0, PersonalLanguageModel(storedWords).usageCount("buddyword", "en-US"))
        assertEquals(0, TypingIntelligence(storedTyping ?: TypingProfileSnapshot()).snapshot().observationCount)
    }

    private fun calibrationOutcome() = TypingOutcome(
        tap = TapPoint(x = 0.6, y = 0.5),
        intendedCharacter = 'q',
        evidence = OutcomeEvidence.EXPLICIT_RETYPE,
        policy = TypingPolicy.LEARNING,
    )
}
