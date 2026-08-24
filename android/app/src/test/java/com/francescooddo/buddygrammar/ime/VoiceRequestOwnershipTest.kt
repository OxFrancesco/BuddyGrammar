package com.francescooddo.buddygrammar.ime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceRequestOwnershipTest {
    @Test
    fun `normal final result consumes the exact request in its field and voice layer`() {
        val ownership = VoiceRequestOwnership()
        val request = ownership.begin(fieldEpoch = 7)

        assertTrue(ownership.isOwner(request, currentFieldEpoch = 7, voiceLayerActive = true))
        assertTrue(ownership.finish(request, currentFieldEpoch = 7, voiceLayerActive = true))
        assertFalse(ownership.isOwner(request, currentFieldEpoch = 7, voiceLayerActive = true))
    }

    @Test
    fun `late callback from an old listener cannot consume a newer generation`() {
        val ownership = VoiceRequestOwnership()
        val firstListenerRequest = ownership.begin(fieldEpoch = 4)
        val secondListenerRequest = ownership.begin(fieldEpoch = 4)

        assertNotEquals(firstListenerRequest, secondListenerRequest)
        assertFalse(
            ownership.finish(
                firstListenerRequest,
                currentFieldEpoch = 4,
                voiceLayerActive = true,
            ),
        )
        assertTrue(
            ownership.finish(
                secondListenerRequest,
                currentFieldEpoch = 4,
                voiceLayerActive = true,
            ),
        )
    }

    @Test
    fun `field switch invalidation rejects field A after field B starts`() {
        val ownership = VoiceRequestOwnership()
        val fieldA = ownership.begin(fieldEpoch = 10)
        ownership.invalidate()
        val fieldB = ownership.begin(fieldEpoch = 11)

        assertFalse(ownership.isOwner(fieldA, currentFieldEpoch = 11, voiceLayerActive = true))
        assertFalse(ownership.finish(fieldA, currentFieldEpoch = 11, voiceLayerActive = true))
        assertTrue(ownership.finish(fieldB, currentFieldEpoch = 11, voiceLayerActive = true))
    }

    @Test
    fun `leaving voice layer or cancellation invalidates callbacks`() {
        val ownership = VoiceRequestOwnership()
        val request = ownership.begin(fieldEpoch = 3)

        assertFalse(ownership.isOwner(request, currentFieldEpoch = 3, voiceLayerActive = false))
        ownership.invalidate()
        assertFalse(ownership.isOwner(request, currentFieldEpoch = 3, voiceLayerActive = true))
    }
}
