package com.francescooddo.buddygrammar.core

import kotlin.system.measureNanoTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardHotPathPerformanceTest {
    @Test
    fun `production lexicon suggestions stay inside the per key cpu budget`() {
        val lexicon = contractLexicon()
        repeat(WARM_UP_ITERATIONS) {
            SuggestionEngine.suggest(
                textBeforeCursor = "performence",
                languageTag = "en-US",
                lexicon = lexicon,
            )
        }

        val samples = List(MEASURED_ITERATIONS) {
            measureNanoTime {
                val suggestions = SuggestionEngine.suggest(
                    textBeforeCursor = "performence",
                    languageTag = "en-US",
                    lexicon = lexicon,
                )
                assertEquals("performance", suggestions.first().text)
            }
        }.sorted()
        val medianMilliseconds = samples[samples.size / 2] / 1_000_000.0

        assertTrue(
            "Median production suggestion latency was ${medianMilliseconds}ms",
            medianMilliseconds < MAX_MEDIAN_MILLISECONDS,
        )
    }

    private companion object {
        const val WARM_UP_ITERATIONS = 3
        const val MEASURED_ITERATIONS = 11
        const val MAX_MEDIAN_MILLISECONDS = 12.0
    }
}
