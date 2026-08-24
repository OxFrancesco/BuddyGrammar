package com.francescooddo.buddygrammar.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

data class HttpResult(val statusCode: Int, val body: ByteArray)

fun interface HttpTransport {
    suspend fun post(request: HttpRequest): HttpResult
}

data class HttpRequest(
    val url: String,
    val contentType: String,
    val headers: Map<String, String>,
    val body: ByteArray,
    val timeoutMillis: Int,
)

class DefaultHttpTransport : HttpTransport {
    override suspend fun post(request: HttpRequest): HttpResult = withContext(Dispatchers.IO) {
        val connection = (URL(request.url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = request.timeoutMillis
            doOutput = true
            setRequestProperty("Content-Type", request.contentType)
            setRequestProperty("Accept", "application/json")
            request.headers.forEach(::setRequestProperty)
        }

        try {
            connection.outputStream.use { it.write(request.body) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            HttpResult(status, stream?.use { it.readBytes() } ?: ByteArray(0))
        } finally {
            connection.disconnect()
        }
    }
}

class BuddyGrammarApi(
    private val transport: HttpTransport = DefaultHttpTransport(),
    private val baseUrl: String = AppConfig.API_BASE_URL,
) {
    suspend fun correct(
        text: String,
        clientId: UUID,
        modelId: String,
        instruction: String,
    ): String {
        val input = text.trim()
        require(input.isNotEmpty()) { "There is no text to correct." }
        val body = JSONObject()
            .put("text", input)
            .put("modelID", modelId)
            .put("instruction", instruction)
            .toString()
            .toByteArray(Charsets.UTF_8)
        val result = transport.post(
            HttpRequest(
                url = "$baseUrl/v1/correct",
                contentType = "application/json",
                headers = mapOf(CLIENT_HEADER to clientId.toString()),
                body = body,
                timeoutMillis = 30_000,
            ),
        )
        val payload = result.body.toString(Charsets.UTF_8)
        if (result.statusCode !in 200..299) throw IOException(serverMessage(payload, result.statusCode))
        val corrected = runCatching { JSONObject(payload).getString("text") }
            .getOrElse { throw IOException("The correction service returned an unreadable response.") }
        return CorrectionOutputGuard.sanitize(corrected, input)
    }

    suspend fun transcribe(
        audio: ByteArray,
        clientId: UUID,
        languageCode: String? = null,
    ): TranscriptResult {
        require(audio.isNotEmpty()) { "The recording did not contain any audio." }
        val headers = buildMap {
            put(CLIENT_HEADER, clientId.toString())
            if (!languageCode.isNullOrBlank()) put(LANGUAGE_HEADER, languageCode)
        }
        val result = transport.post(
            HttpRequest(
                url = "$baseUrl/v1/transcribe",
                contentType = "audio/mp4",
                headers = headers,
                body = audio,
                timeoutMillis = 95_000,
            ),
        )
        val payload = result.body.toString(Charsets.UTF_8)
        if (result.statusCode !in 200..299) throw IOException(serverMessage(payload, result.statusCode))
        return runCatching {
            val json = JSONObject(payload)
            TranscriptResult(
                text = json.getString("text").trim().ifEmpty {
                    throw IOException("ElevenLabs could not hear speech in the recording.")
                },
                languageCode = json.optString("language_code").takeIf { it.isNotBlank() },
                languageProbability = json.optDouble("language_probability").takeIf { !it.isNaN() },
            )
        }.getOrElse {
            if (it is IOException) throw it
            throw IOException("The transcription service returned an unreadable response.")
        }
    }

    suspend fun recognizeHandwriting(
        imagePng: ByteArray,
        clientId: UUID,
        modelId: String,
        languageCode: String? = null,
    ): String {
        require(imagePng.isNotEmpty()) { "There is no handwriting to recognize." }
        val headers = buildMap {
            put(CLIENT_HEADER, clientId.toString())
            put(MODEL_HEADER, modelId)
            if (!languageCode.isNullOrBlank()) put(LANGUAGE_HEADER, languageCode)
        }
        val result = transport.post(
            HttpRequest(
                url = "$baseUrl/v1/handwriting",
                contentType = "image/png",
                headers = headers,
                body = imagePng,
                timeoutMillis = 30_000,
            ),
        )
        val payload = result.body.toString(Charsets.UTF_8)
        if (result.statusCode !in 200..299) throw IOException(serverMessage(payload, result.statusCode))
        return runCatching { JSONObject(payload).getString("text").trim() }
            .getOrElse { throw IOException("The handwriting service returned an unreadable response.") }
            .ifEmpty { throw IOException("BuddyGrammar could not read that handwriting.") }
    }

    private fun serverMessage(payload: String, statusCode: Int): String = runCatching {
        JSONObject(payload).getJSONObject("error").getString("message")
    }.getOrDefault("The processing service returned HTTP $statusCode.")

    companion object {
        const val CLIENT_HEADER = "X-BuddyGrammar-Client-ID"
        const val LANGUAGE_HEADER = "X-Buddy-Language-Code"
        const val MODEL_HEADER = "X-Buddy-Model-ID"
    }
}
