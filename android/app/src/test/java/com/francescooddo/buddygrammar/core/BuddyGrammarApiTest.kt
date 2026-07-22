package com.francescooddo.buddygrammar.core

import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.UUID

class BuddyGrammarApiTest {
    private val clientId = UUID.fromString("83001d6e-7daa-4bb5-ac9a-07f70129ad11")

    @Test
    fun `correction request uses worker contract without provider credentials`() = runTest {
        var captured: HttpRequest? = null
        val api = BuddyGrammarApi(
            transport = HttpTransport { request ->
                captured = request
                HttpResult(200, "{\"text\":\"This is correct.\"}".toByteArray())
            },
            baseUrl = "https://example.test",
        )

        val output = api.correct("this are correct", clientId, "test/model", "Correct it.")

        assertEquals("This is correct.", output)
        val request = checkNotNull(captured)
        assertEquals("https://example.test/v1/correct", request.url)
        assertEquals("application/json", request.contentType)
        assertEquals(clientId.toString(), request.headers[BuddyGrammarApi.CLIENT_HEADER])
        assertFalse(request.headers.containsKey("Authorization"))
        assertFalse(request.headers.containsKey("xi-api-key"))
        val json = JSONObject(request.body.toString(Charsets.UTF_8))
        assertEquals("this are correct", json.getString("text"))
        assertEquals("test/model", json.getString("modelID"))
        assertEquals("Correct it.", json.getString("instruction"))
        assertEquals(setOf("text", "modelID", "instruction"), json.keys().asSequence().toSet())
    }

    @Test
    fun `transcription sends raw audio and parses language metadata`() = runTest {
        var captured: HttpRequest? = null
        val api = BuddyGrammarApi(
            transport = HttpTransport { request ->
                captured = request
                HttpResult(
                    200,
                    "{\"text\":\"Hello.\",\"language_code\":\"eng\",\"language_probability\":0.98}"
                        .toByteArray(),
                )
            },
            baseUrl = "https://example.test",
        )

        val audio = byteArrayOf(1, 2, 3)
        val result = api.transcribe(audio, clientId, "en")

        val request = checkNotNull(captured)
        assertEquals("audio/mp4", request.contentType)
        assertArrayEquals(audio, request.body)
        assertEquals("en", request.headers[BuddyGrammarApi.LANGUAGE_HEADER])
        assertNull(request.headers["X-Buddy-Audio-Filename"])
        assertEquals("Hello.", result.text)
        assertEquals("eng", result.languageCode)
        assertEquals(0.98, result.languageProbability ?: 0.0, 0.001)
    }

    @Test
    fun `handwriting fallback sends png with model and language headers`() = runTest {
        var captured: HttpRequest? = null
        val api = BuddyGrammarApi(
            transport = HttpTransport { request ->
                captured = request
                HttpResult(200, "{\"text\":\"Hello\"}".toByteArray())
            },
            baseUrl = "https://example.test",
        )
        val png = byteArrayOf(0x13, 0x37)

        val result = api.recognizeHandwriting(png, clientId, "test/model", "en")

        assertEquals("Hello", result)
        val request = checkNotNull(captured)
        assertEquals("https://example.test/v1/handwriting", request.url)
        assertEquals("image/png", request.contentType)
        assertArrayEquals(png, request.body)
        assertEquals(clientId.toString(), request.headers[BuddyGrammarApi.CLIENT_HEADER])
        assertEquals("test/model", request.headers[BuddyGrammarApi.MODEL_HEADER])
        assertEquals("en", request.headers[BuddyGrammarApi.LANGUAGE_HEADER])
        assertFalse(request.headers.containsKey("Authorization"))
    }
}
