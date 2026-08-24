package com.francescooddo.buddygrammar.ime

/** Immutable identity captured by the RecognitionListener created for one start request. */
internal data class VoiceRequestToken(
    val generation: Long,
    val fieldEpoch: Long,
)

/**
 * Single-owner gate for speech callbacks.
 *
 * A callback is publishable only while its immutable generation is active, its original field is
 * still current, and the keyboard is still on the voice layer.
 */
internal class VoiceRequestOwnership {
    private var generation = 0L
    private var activeRequest: VoiceRequestToken? = null

    fun begin(fieldEpoch: Long): VoiceRequestToken = VoiceRequestToken(
        generation = ++generation,
        fieldEpoch = fieldEpoch,
    ).also { activeRequest = it }

    fun isOwner(
        request: VoiceRequestToken,
        currentFieldEpoch: Long,
        voiceLayerActive: Boolean,
    ): Boolean = voiceLayerActive &&
        request.fieldEpoch == currentFieldEpoch &&
        activeRequest == request

    fun finish(
        request: VoiceRequestToken,
        currentFieldEpoch: Long,
        voiceLayerActive: Boolean,
    ): Boolean {
        if (!isOwner(request, currentFieldEpoch, voiceLayerActive)) return false
        activeRequest = null
        return true
    }

    fun invalidate() {
        generation += 1
        activeRequest = null
    }
}
