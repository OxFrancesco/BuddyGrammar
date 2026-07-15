package com.francescooddo.buddygrammar.ui

import java.io.IOException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptionRetryTest {
    @Test
    fun `a failed transcription is retried once`() = runTest {
        var attempts = 0

        val result = retryTranscriptionOnce(delayMillis = 0) {
            attempts += 1
            if (attempts == 1) throw IOException("temporary failure")
            "completed"
        }

        assertEquals("completed", result)
        assertEquals(2, attempts)
    }

    @Test
    fun `two failures ask the user to try again later`() = runTest {
        var attempts = 0

        val failure = runCatching {
            retryTranscriptionOnce<Unit>(delayMillis = 0) {
                attempts += 1
                throw IOException("service unavailable")
            }
        }.exceptionOrNull()

        assertEquals(2, attempts)
        assertTrue(failure is IOException)
        assertTrue(failure?.message?.contains("try again later") == true)
    }
}
