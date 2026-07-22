package com.francescooddo.buddygrammar.core.adaptive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TypingIntelligenceTest {
    @Test
    fun `strong continuation can claim an ambiguous adjacent edge tap`() {
        val intelligence = TypingIntelligence()

        val result = intelligence.resolve(
            tap = TapPoint(x = 3.12, y = 0.50),
            context = TypingContext(currentWordPrefix = "hom"),
        )

        assertEquals('r', result.literalCharacter)
        assertEquals('e', result.character)
        assertTrue(result.wasAdapted)
        assertEquals('e', result.candidates.first().character)
        assertTrue(result.candidates.any { it.character == 'r' })
        assertTrue(result.candidates.all { it.character in setOf('e', 'r', 't', 'd', 'f') })
        assertEquals(1.0, result.candidates.sumOf { it.confidence }, 0.000_001)
    }

    @Test
    fun `explicit practice feedback updates a bounded aggregate profile`() {
        val intelligence = TypingIntelligence()

        intelligence.observe(
            TypingOutcome(
                tap = TapPoint(x = 2.70, y = 0.40),
                intendedCharacter = 'e',
                evidence = OutcomeEvidence.PRACTICE_TARGET,
                policy = TypingPolicy.PRACTICE,
            ),
        )

        val profile = intelligence.snapshot()
        assertEquals(1, profile.observationCount)
        assertEquals(0.20, profile.meanOffsetX, 0.000_001)
        assertEquals(-0.10, profile.meanOffsetY, 0.000_001)
        assertEquals(1, profile.keyOffsets.getValue("e").observationCount)
        assertEquals(0.20, profile.keyOffsets.getValue("e").meanOffsetX, 0.000_001)
    }

    @Test
    fun `explicit retype feedback is learnable in normal learning mode`() {
        val intelligence = TypingIntelligence()

        intelligence.observe(
            TypingOutcome(
                tap = TapPoint(x = 5.20, y = 1.40),
                intendedCharacter = 'h',
                evidence = OutcomeEvidence.EXPLICIT_RETYPE,
                policy = TypingPolicy.LEARNING,
            ),
        )

        assertEquals(1, intelligence.snapshot().observationCount)
    }

    @Test
    fun `read only resolution applies a restored personal mean offset`() {
        val intelligence = TypingIntelligence(
            initialProfile = TypingProfileSnapshot(
                observationCount = 20,
                meanOffsetX = 0.30,
                meanOffsetY = 0.0,
            ),
        )

        val result = intelligence.resolve(
            tap = TapPoint(x = 3.10, y = 0.50),
            context = TypingContext(
                currentWordPrefix = "xyz",
                policy = TypingPolicy.READ_ONLY,
            ),
        )

        assertEquals('r', result.literalCharacter)
        assertEquals('e', result.character)
    }

    @Test
    fun `repeated explicit calibration changes later border resolution`() {
        val intelligence = TypingIntelligence()
        repeat(5) {
            intelligence.observe(
                TypingOutcome(
                    tap = TapPoint(x = 2.80, y = 0.50),
                    intendedCharacter = 'e',
                    evidence = OutcomeEvidence.EXPLICIT_RETYPE,
                    policy = TypingPolicy.LEARNING,
                ),
            )
        }

        val result = intelligence.resolve(
            tap = TapPoint(x = 3.10, y = 0.50),
            context = TypingContext(currentWordPrefix = "xyz", policy = TypingPolicy.READ_ONLY),
        )

        assertEquals('e', result.character)
    }

    @Test
    fun `per key calibration does not move an unrelated region`() {
        val intelligence = TypingIntelligence()
        repeat(8) {
            intelligence.observe(
                TypingOutcome(
                    tap = TapPoint(x = 2.80, y = 0.50),
                    intendedCharacter = 'e',
                    evidence = OutcomeEvidence.EXPLICIT_RETYPE,
                    policy = TypingPolicy.LEARNING,
                ),
            )
        }

        val unrelated = intelligence.resolve(
            tap = TapPoint(x = 8.05, y = 0.50),
            context = TypingContext(currentWordPrefix = "xyz", policy = TypingPolicy.READ_ONLY),
        )

        assertEquals('o', unrelated.literalCharacter)
        assertEquals('o', unrelated.character)
        assertTrue("o" !in intelligence.snapshot().keyOffsets)
    }

    @Test
    fun `central anchors remain literal even with strong context`() {
        val result = TypingIntelligence().resolve(
            tap = TapPoint(x = 3.50, y = 0.50),
            context = TypingContext(currentWordPrefix = "hom"),
        )

        assertEquals('r', result.character)
    }

    @Test
    fun `missing prior evidence leaves an ambiguous tap literal`() {
        val result = TypingIntelligence().resolve(
            tap = TapPoint(x = 3.12, y = 0.50),
            context = TypingContext(currentWordPrefix = "xyz"),
        )

        assertEquals('r', result.character)
    }

    @Test
    fun `equal continuation priors leave an ambiguous tap literal`() {
        val result = TypingIntelligence().resolve(
            tap = TapPoint(x = 7.55, y = 2.50),
            context = TypingContext(currentWordPrefix = "co"),
        )

        assertEquals('m', result.character)
    }

    @Test
    fun `non English context safely falls back to literal resolution`() {
        val result = TypingIntelligence().resolve(
            tap = TapPoint(x = 3.12, y = 0.50),
            context = TypingContext(currentWordPrefix = "hom", languageTag = "it-IT"),
        )

        assertEquals('r', result.character)
    }

    @Test
    fun `generic resolution ignores a restored personal profile`() {
        val intelligence = TypingIntelligence(
            initialProfile = TypingProfileSnapshot(
                observationCount = 20,
                meanOffsetX = 0.30,
            ),
        )

        val result = intelligence.resolve(
            tap = TapPoint(x = 3.10, y = 0.50),
            context = TypingContext(currentWordPrefix = "xyz", policy = TypingPolicy.GENERIC),
        )

        assertEquals('r', result.character)
    }

    @Test
    fun `decoder output is never accepted as its own intended label`() {
        val intelligence = TypingIntelligence()

        intelligence.observe(
            TypingOutcome(
                tap = TapPoint(x = 2.70, y = 0.40),
                intendedCharacter = 'e',
                evidence = OutcomeEvidence.DECODER_OUTPUT,
                policy = TypingPolicy.PRACTICE,
            ),
        )

        assertEquals(TypingProfileSnapshot(), intelligence.snapshot())
    }

    @Test
    fun `non learning policies record no feedback`() {
        val intelligence = TypingIntelligence()

        listOf(
            TypingPolicy.GENERIC,
            TypingPolicy.READ_ONLY,
            TypingPolicy.LITERAL,
            TypingPolicy.SENSITIVE,
        ).forEach { policy ->
            intelligence.observe(
                TypingOutcome(
                    tap = TapPoint(x = 2.70, y = 0.40),
                    intendedCharacter = 'e',
                    evidence = OutcomeEvidence.EXPLICIT_RETYPE,
                    policy = policy,
                ),
            )
        }

        assertEquals(0, intelligence.snapshot().observationCount)
    }

    @Test
    fun `literal and sensitive resolution bypass contextual adaptation`() {
        listOf(TypingPolicy.LITERAL, TypingPolicy.SENSITIVE).forEach { policy ->
            val result = TypingIntelligence().resolve(
                tap = TapPoint(x = 3.12, y = 0.50),
                context = TypingContext(currentWordPrefix = "hom", policy = policy),
            )

            assertEquals('r', result.character)
        }
    }

    @Test
    fun `outlier feedback cannot move aggregate means beyond half a key`() {
        val intelligence = TypingIntelligence()

        intelligence.observe(
            TypingOutcome(
                tap = TapPoint(x = 100.0, y = 100.0),
                intendedCharacter = 'e',
                evidence = OutcomeEvidence.PRACTICE_TARGET,
                policy = TypingPolicy.PRACTICE,
            ),
        )

        val profile = intelligence.snapshot()
        assertEquals(0.50, profile.meanOffsetX, 0.0)
        assertEquals(0.50, profile.meanOffsetY, 0.0)
    }
}
