package com.francescooddo.buddygrammar.core.adaptive

import com.francescooddo.buddygrammar.core.contractLexicon
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

    @Test
    fun `language scoped priors choose date in English and dare in Italian`() {
        val taps = literalTaps("da") + TapWordLatticeTap(
            literalKey = 't',
            resolvedKey = 't',
            candidates = listOf(KeyCandidate('t', 0.5), KeyCandidate('r', 0.5)),
        ) + literalTap('e')
        val decoder = TapWordDecoder(contractLexicon())

        assertEquals("date", decoder.decode(taps, languageTag = "en-GB").candidates.first().word)
        val italian = decoder.decode(taps, languageTag = "it-CH")
        assertEquals("dare", italian.candidates.first().word)
        assertTrue(italian.candidates.any { it.word == "date" && it.isLiteralPath })
    }

    @Test
    fun `Italian geometry restores canonical accent and apostrophe`() {
        val decoder = TapWordDecoder(contractLexicon())
        val accented = decoder.decode(
            taps = literalTaps("perch") + TapWordLatticeTap(
                literalKey = 'r',
                resolvedKey = 'r',
                candidates = listOf(KeyCandidate('r', 0.52), KeyCandidate('e', 0.48)),
            ),
            languageTag = "it-IT",
        )
        val elision = decoder.decode(
            taps = literalTaps("lh") + TapWordLatticeTap(
                literalKey = 'p',
                resolvedKey = 'p',
                candidates = listOf(KeyCandidate('p', 0.52), KeyCandidate('o', 0.48)),
            ),
            languageTag = "it",
        )

        assertEquals("perché", accented.candidates.first().word)
        assertTrue(accented.candidates.any { it.word == "perchr" && it.isLiteralPath })
        assertEquals("l’ho", elision.candidates.first().word)
        assertTrue(elision.candidates.any { it.word == "lhp" && it.isLiteralPath })
    }

    @Test
    fun `automatic policy abstains from balanced out of vocabulary lattice`() {
        val taps = literalTaps("qwe") + TapWordLatticeTap(
            literalKey = 'r',
            resolvedKey = 'r',
            candidates = listOf(KeyCandidate('r', 0.5), KeyCandidate('t', 0.5)),
        )
        val result = TapWordDecoder(contractLexicon()).decode(taps, languageTag = "en")

        assertEquals("qwer", result.candidates.first().word)
        assertEquals(null, TapWordAcceptancePolicy.AUTOMATIC.acceptedCandidate(result))
        assertEquals(null, TapWordAcceptancePolicy.SUGGESTION.acceptedCandidate(result))
    }

    @Test
    fun acceptedTapReplacementRespectsNeverSuggestSuppression() {
        val result = TapWordDecodingResult(
            literalWord = "dste",
            resolvedWord = "date",
            candidates = listOf(
                TapWordCandidate(
                    word = "date",
                    score = 1.0,
                    confidence = 0.85,
                    isLiteralPath = false,
                    isResolvedPath = true,
                ),
                TapWordCandidate(
                    word = "dste",
                    score = 0.1,
                    confidence = 0.15,
                    isLiteralPath = true,
                    isResolvedPath = false,
                ),
            ),
            margin = 0.70,
        )

        assertEquals(
            null,
            TapWordAcceptancePolicy.AUTOMATIC.acceptedReplacement(
                result = result,
                visibleWord = "dste",
                isSuppressed = { typed, suggestion ->
                    typed == "dste" && suggestion == "date"
                },
            ),
        )
        assertEquals(
            "date",
            TapWordAcceptancePolicy.AUTOMATIC.acceptedReplacement(
                result = result,
                visibleWord = "dste",
                isSuppressed = { _, _ -> false },
            ),
        )
    }

    @Test
    fun straightAndCurlyApostrophesUseLetterOnlyTapGeometry() {
        assertEquals(3, TapWordDecoder.expectedTapCount("l'ho"))
        assertEquals(3, TapWordDecoder.expectedTapCount("l’ho"))
        assertEquals(6, TapWordDecoder.expectedTapCount("perché"))
        assertEquals(null, TapWordDecoder.expectedTapCount("abc123"))
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
