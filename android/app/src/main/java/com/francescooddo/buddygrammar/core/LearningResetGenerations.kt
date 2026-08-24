package com.francescooddo.buddygrammar.core

/** Monotonic reset epochs shared by the settings app and a live IME process. */
data class LearningResetGenerations(
    val typingProfile: Long = 0,
    val personalLanguageModel: Long = 0,
)

data class LearningResetChanges(
    val typingProfileChanged: Boolean,
    val personalLanguageModelChanged: Boolean,
) {
    val hasChanges: Boolean get() = typingProfileChanged || personalLanguageModelChanged
}

/** Tracks which persisted learning epochs the live keyboard currently owns. */
class LiveLearningResetState(initial: LearningResetGenerations) {
    var generations: LearningResetGenerations = initial
        private set

    fun reconcile(latest: LearningResetGenerations): LearningResetChanges {
        val changes = LearningResetChanges(
            typingProfileChanged = latest.typingProfile != generations.typingProfile,
            personalLanguageModelChanged =
                latest.personalLanguageModel != generations.personalLanguageModel,
        )
        generations = latest
        return changes
    }

    fun ownsTypingProfile(generation: Long): Boolean =
        generations.typingProfile == generation

    fun ownsPersonalLanguageModel(generation: Long): Boolean =
        generations.personalLanguageModel == generation
}
