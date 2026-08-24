package com.francescooddo.buddygrammar.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject
import java.io.File

class SwipeTypingEngineTest {
    private val engine = SwipeTypingEngine(
        words = listOf("the", "there", "three", "hello", "help", "world"),
    )

    @Test
    fun `ranks an exact key trace first`() {
        assertEquals("hello", engine.candidates("helo").first())
        assertEquals("world", engine.candidates("world").first())
    }

    @Test
    fun `rejects a gesture whose anchors do not match the vocabulary`() {
        assertTrue(engine.candidates("qaz").isEmpty())
    }

    @Test
    fun `returns no candidates for a tap`() {
        assertTrue(engine.candidates("h").isEmpty())
    }

    @Test
    fun `timed recognition matches shared repeated letter dwell contract`() {
        val cases = loadSharedDwellSuite().getJSONArray("cases")
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val input = case.getJSONObject("input")
            val expectedWord = case.getJSONObject("expect").getString("keySequence")
            val collapsedWord = expectedWord.fold(StringBuilder()) { letters, letter ->
                if (letters.lastOrNull() != letter) letters.append(letter)
                letters
            }.toString()
            val alternate = if (expectedWord == collapsedWord) {
                expectedWord.substring(0, 1) + expectedWord[1] + expectedWord.substring(1)
            } else {
                collapsedWord
            }
            val languageId = input.getString("languageId")
            val samplesJson = input.getJSONArray("samples")
            val samples = (0 until samplesJson.length()).map { sampleIndex ->
                samplesJson.getJSONObject(sampleIndex).let { sample ->
                    SwipePathSample(
                        x = sample.getDouble("x"),
                        y = sample.getDouble("y"),
                        timestampMilliseconds = sample.getDouble("atMilliseconds"),
                    )
                }
            }
            val fixtureEngine = SwipeTypingEngine(
                words = emptyList(),
                languageWords = mapOf(languageId to listOf(alternate, expectedWord)),
            )

            val result = fixtureEngine.recognize(
                samples = samples,
                limit = 2,
                languageTag = languageId,
            )

            assertEquals("${case.getString("id")}: $result", expectedWord, result.acceptedCandidate?.word)
            assertFalse("${case.getString("id")}: $result", result.abstained)
            assertTrue(case.getString("id"), result.confidence > 0.0)
            assertTrue(case.getString("id"), result.margin > 0.0)
            assertEquals(expectedWord, result.candidates.first().word)
            assertTrue(
                "${case.getString("id")}: expected post-swipe alternate $alternate, got $result",
                result.candidates.drop(1).any { it.word == alternate },
            )
        }
    }

    @Test
    fun `timed recognition abstains when top candidates are ambiguous`() {
        val result = SwipeTypingEngine(words = listOf("cat", "car")).recognize(
            samples = listOf(
                SwipePathSample(x = 2.75, y = 2.0, timestampMilliseconds = 0.0),
                SwipePathSample(x = 0.25, y = 1.0, timestampMilliseconds = 100.0),
                // Slightly favors the lower-ranked "car" geometry so the
                // frequency prior and path likelihood cancel each other.
                SwipePathSample(x = 3.20, y = 0.0, timestampMilliseconds = 200.0),
            ),
            limit = 2,
        )

        assertTrue("got $result", result.abstained)
        assertNull(result.acceptedCandidate)
        assertEquals(SwipeAbstentionReason.AMBIGUOUS, result.abstentionReason)
        assertEquals(2, result.candidates.size)
        assertTrue("got ${result.margin}", result.margin < 0.03)
    }

    @Test
    fun `Italian display spelling matches shared recognition traces`() {
        val cases = loadSharedSuite("swipe-recognition.json").getJSONArray("cases")
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val input = case.getJSONObject("input")
            val languageId = input.getString("languageId")
            val vocabularyJson = input.getJSONArray("vocabulary")
            val vocabulary = (0 until vocabularyJson.length()).map(vocabularyJson::getString)
            val samplesJson = input.getJSONArray("samples")
            val samples = (0 until samplesJson.length()).map { sampleIndex ->
                samplesJson.getJSONObject(sampleIndex).let { sample ->
                    SwipePathSample(
                        x = sample.getDouble("x"),
                        y = sample.getDouble("y"),
                        timestampMilliseconds = sample.getDouble("atMilliseconds"),
                    )
                }
            }
            val expected = case.getJSONObject("expect")
            val expectedDisplayWord = expected.getString("displayWord")
            val expectedGeometry = expected.getString("geometryKey")
            val engine = SwipeTypingEngine(
                words = emptyList(),
                languageWords = mapOf(languageId to vocabulary),
            )

            val result = engine.recognize(
                samples = samples,
                limit = vocabulary.size,
                languageTag = languageId,
            )

            assertEquals("${case.getString("id")}: $result", expectedDisplayWord, result.acceptedCandidate?.word)
            assertEquals(expectedDisplayWord, result.candidates.firstOrNull()?.word)
            assertEquals(expectedGeometry, SwipeWordNormalizer.normalize(expectedDisplayWord)?.geometry)
        }
    }

    private fun loadSharedDwellSuite(): JSONObject {
        return loadSharedSuite("swipe-dwell.json")
    }

    private fun loadSharedSuite(fileName: String): JSONObject {
        val workingDirectory = requireNotNull(System.getProperty("user.dir")) {
            "user.dir must be available while loading swipe fixtures"
        }
        var directory = File(workingDirectory).canonicalFile
        repeat(6) {
            val fixture = File(
                directory,
                "shared/keyboard-contract/v1/traces/$fileName",
            )
            if (fixture.isFile) return JSONObject(fixture.readText())
            directory = directory.parentFile
                ?: error("Could not locate shared $fileName from $workingDirectory")
        }
        error("Could not locate shared $fileName from $workingDirectory")
    }
}
