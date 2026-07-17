package com.francescooddo.buddygrammar.core.adaptive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TapWordDecoderTest {
    @Test
    fun `ambiguous final tap decodes homr to home and preserves literal path`() {
        val taps = literalTaps("hom") + TapWordLatticeTap(
            literalKey = 'r',
            resolvedKey = 'r',
            candidates = listOf(
                KeyCandidate('r', 0.52),
                KeyCandidate('e', 0.48),
            ),
        )

        val result = TapWordDecoder().decode(taps, languageTag = "en-US")

        assertEquals("home", result.candidates.first().word)
        assertEquals("homr", result.literalWord)
        assertEquals("homr", result.resolvedWord)
        assertTrue(result.candidates.any { it.word == "homr" && it.isLiteralPath })
        assertTrue(result.margin > 0.0)
    }

    @Test
    fun `previous word context raises an English continuation score`() {
        val taps = literalTaps("bac") + TapWordLatticeTap(
            literalKey = 'j',
            resolvedKey = 'j',
            candidates = listOf(
                KeyCandidate('j', 0.52),
                KeyCandidate('k', 0.48),
            ),
        )
        val decoder = TapWordDecoder()

        val withoutContext = decoder.decode(taps, languageTag = "en")
        val withContext = decoder.decode(
            taps = taps,
            previousWord = "come",
            languageTag = "en-US",
        )

        val plainBack = withoutContext.candidates.single { it.word == "back" }
        val contextualBack = withContext.candidates.single { it.word == "back" }
        assertTrue(contextualBack.score > plainBack.score)
    }

    @Test
    fun `literal proper name and resolved OOV paths always survive ranking`() {
        val literal = "Francescp"
        val taps = literal.mapIndexed { index, character ->
            if (index == literal.lastIndex) {
                TapWordLatticeTap(
                    literalKey = character,
                    resolvedKey = 'o',
                    candidates = listOf(
                        KeyCandidate('o', 0.99),
                        KeyCandidate('p', 0.01),
                    ),
                )
            } else {
                literalTap(character)
            }
        }

        val result = TapWordDecoder().decode(taps, languageTag = "en", limit = 2)

        assertEquals("Francescp", result.literalWord)
        assertEquals("Francesco", result.resolvedWord)
        assertTrue(result.candidates.any {
            it.word == "Francescp" && it.isLiteralPath
        })
        assertTrue(result.candidates.any {
            it.word == "Francesco" && it.isResolvedPath
        })
    }

    @Test
    fun `literal only taps remain unchanged with full confidence`() {
        val result = TapWordDecoder().decode(literalTaps("cat"), languageTag = "en")

        assertEquals("cat", result.literalWord)
        assertEquals("cat", result.resolvedWord)
        assertEquals(listOf("cat"), result.candidates.map { it.word })
        assertEquals(1.0, result.candidates.single().confidence, 0.0)
        assertEquals(1.0, result.margin, 0.0)
    }

    @Test
    fun `malformed and oversized lattices fail closed within public bounds`() {
        val decoder = TapWordDecoder()
        val oversized = List(TapWordDecoder.MAXIMUM_TAPS + 1) { literalTap('a') }
        assertTrue(decoder.decode(oversized).candidates.isEmpty())
        assertTrue(decoder.decode(emptyList()).candidates.isEmpty())
        assertTrue(
            decoder.decode(
                listOf(
                    TapWordLatticeTap(
                        literalKey = '1',
                        resolvedKey = '1',
                        candidates = emptyList(),
                    ),
                ),
            ).candidates.isEmpty(),
        )

        val nonAdjacent = TapWordLatticeTap(
            literalKey = 'a',
            resolvedKey = 'p',
            candidates = listOf(
                KeyCandidate('p', 0.99),
                KeyCandidate('a', Double.NaN),
            ),
        )
        assertEquals(
            listOf("a"),
            decoder.decode(listOf(nonAdjacent), languageTag = "en")
                .candidates
                .map { it.word },
        )

        val crowdedTap = TapWordLatticeTap(
            literalKey = 'g',
            resolvedKey = 'g',
            candidates = listOf('g', 'f', 'h', 't', 'y', 'v', 'b').map {
                KeyCandidate(it, 1.0)
            },
        )
        val bounded = decoder.decode(List(4) { crowdedTap }, limit = Int.MAX_VALUE)
        assertTrue(bounded.candidates.size <= TapWordDecoder.MAXIMUM_RESULTS)
        assertTrue(bounded.candidates.all { it.word.length == 4 })
    }

    @Test
    fun `non English decoding uses spatial evidence without English lexicon bias`() {
        val taps = literalTaps("hom") + TapWordLatticeTap(
            literalKey = 'r',
            resolvedKey = 'r',
            candidates = listOf(
                KeyCandidate('r', 0.52),
                KeyCandidate('e', 0.48),
            ),
        )

        val result = TapWordDecoder().decode(taps, languageTag = "it-IT")

        assertEquals("homr", result.candidates.first().word)
    }

    @Test
    fun `identical input produces identical ranking confidence and margin`() {
        val taps = literalTaps("bac") + TapWordLatticeTap(
            literalKey = 'j',
            resolvedKey = 'k',
            candidates = listOf(
                KeyCandidate('j', 0.5),
                KeyCandidate('k', 0.5),
            ),
        )
        val decoder = TapWordDecoder()

        val first = decoder.decode(taps, previousWord = "come", languageTag = "en-US")
        val second = decoder.decode(taps, previousWord = "come", languageTag = "en-US")

        assertEquals(first, second)
    }

    @Test
    fun `lattice tap can be created directly from a key resolution`() {
        val resolution = KeyResolution(
            character = 'e',
            literalCharacter = 'r',
            confidence = 0.6,
            candidates = listOf(
                KeyCandidate('e', 0.6),
                KeyCandidate('r', 0.4),
            ),
        )

        val tap = TapWordLatticeTap(resolution = resolution, literalTap = 'r')

        assertEquals('r', tap.literalKey)
        assertEquals('e', tap.resolvedKey)
        assertEquals(resolution.candidates, tap.candidates)
    }

    private fun literalTaps(word: String): List<TapWordLatticeTap> = word.map { character ->
        literalTap(character)
    }

    private fun literalTap(character: Char) = TapWordLatticeTap(
        literalKey = character,
        resolvedKey = character,
        candidates = listOf(KeyCandidate(character, 1.0)),
    )
}
