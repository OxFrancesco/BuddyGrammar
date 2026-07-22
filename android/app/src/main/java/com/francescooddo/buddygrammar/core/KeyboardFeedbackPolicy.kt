package com.francescooddo.buddygrammar.core

object KeyboardFeedbackPolicy {
    fun shouldPlayStandardClick(
        feedback: InteractionFeedback,
        systemSoundEffectsEnabled: Boolean,
        ringerModeNormal: Boolean,
    ): Boolean = feedback == InteractionFeedback.KEY &&
        systemSoundEffectsEnabled &&
        ringerModeNormal
}
