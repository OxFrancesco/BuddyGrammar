package com.francescooddo.buddygrammar.core

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.francescooddo.buddygrammar.core.adaptive.TypingProfileSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PreferencesRepositoryResetInstrumentedTest {
    @Test
    fun resetEpochsRejectWritesFromModelsThatOwnedThePreviousGeneration() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val repository = PreferencesRepository(context)
        repository.clearTypingProfile()
        repository.clearPersonalLanguageModel()
        val before = repository.loadLearningResetGenerations()

        assertEquals(
            true,
            repository.saveTypingProfile(
                TypingProfileSnapshot(observationCount = 8),
                expectedResetGeneration = before.typingProfile,
            ),
        )
        assertEquals(
            true,
            repository.savePersonalLanguageModel(
                data = "su en buddyword 4\n",
                expectedResetGeneration = before.personalLanguageModel,
            ),
        )

        repository.clearTypingProfile()
        repository.clearPersonalLanguageModel()
        val after = repository.loadLearningResetGenerations()

        assertNotEquals(before.typingProfile, after.typingProfile)
        assertNotEquals(before.personalLanguageModel, after.personalLanguageModel)
        assertFalse(
            repository.saveTypingProfile(
                TypingProfileSnapshot(observationCount = 9),
                expectedResetGeneration = before.typingProfile,
            ),
        )
        assertFalse(
            repository.savePersonalLanguageModel(
                data = "su en resurrected 5\n",
                expectedResetGeneration = before.personalLanguageModel,
            ),
        )
        assertEquals(0, repository.loadTypingProfile().observationCount)
        assertNull(repository.loadPersonalLanguageModel())
    }
}
