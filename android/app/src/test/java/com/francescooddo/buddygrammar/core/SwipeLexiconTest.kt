package com.francescooddo.buddygrammar.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SwipeLexiconTest {
    @Test
    fun `parser preserves Unicode spelling and canonicalizes apostrophes`() {
        assertEquals(
            listOf("perché", "caffè", "l’ho", "po’"),
            SwipeLexicon.parse("# v1\nperché\ncaffè\nl'ho\npoʼ\n"),
        )
    }

    @Test
    fun `parser rejects duplicate canonical spelling and non swipe entries`() {
        listOf(
            "ciao\nciao\n",
            "l'ho\nl’ho\n",
            "ciao\ndue parole\n",
            "ciao\n'aperto\n",
            "ciao\nl''ho\n",
            "ciao\nperché!\n",
            "ciao\nÈ\n",
            "ciao\nгород\n",
        ).forEach { malformed ->
            val failure = runCatching { SwipeLexicon.parse(malformed) }.exceptionOrNull()
            assertTrue("Expected malformed lexicon to fail: $malformed", failure is IllegalArgumentException)
        }
    }

    @Test
    fun `Android bundles the canonical curated Italian v1 swipe lexicon byte for byte`() {
        val root = repositoryRoot()
        val canonical = File(root, "shared/keyboard-contract/v1/lexicons/it-core.txt")
        val androidCopy = File(root, "android/app/src/main/res/raw/swipe_lexicon_it_v1.txt")

        assertTrue("Missing canonical Italian swipe lexicon", canonical.isFile)
        assertTrue("Missing Android Italian swipe lexicon", androidCopy.isFile)
        assertEquals(canonical.readBytes().toList(), androidCopy.readBytes().toList())

        val words = SwipeLexicon.parse(canonical.readText())
        assertTrue("Expected a useful core lexicon, got ${words.size} words", words.size >= 500)
        assertEquals(listOf("essere", "avere", "fare", "dire", "andare"), words.take(5))
        listOf(
            "ciao",
            "grazie",
            "perché",
            "più",
            "caffè",
            "l’ho",
            "po’",
            "francesco",
            "giulia",
            "meeting",
            "feedback",
            "deadline",
            "whatsapp",
            "buongiorno",
            "stasera",
            "lavoro",
            "famiglia",
            "messaggio",
            "appuntamento",
        ).forEach { word -> assertTrue("Missing everyday Italian word $word", word in words) }
        listOf(
            "perche", "puo", "gia", "piu", "pero", "cioe", "cosi",
            "lunedi", "martedi", "mercoledi", "giovedi", "venerdi",
            "papa", "universita", "attivita", "societa", "caffe", "menu", "citta",
        ).forEach { misspelling ->
            assertFalse("Unexpected unaccented duplicate $misspelling", misspelling in words)
        }
    }

    @Test
    fun `recognition folds accents and apostrophes but returns display spelling`() {
        val engine = SwipeTypingEngine(
            words = emptyList(),
            languageWords = mapOf("it" to listOf("perché", "l’ho", "po’")),
        )

        fun recognize(geometry: String): String? {
            val samples = geometry.mapIndexed { index, character ->
                val point = requireNotNull(QwertyKeyLayout.center(character))
                SwipePathSample(point.x, point.y, index * 90.0)
            }
            return engine.recognize(samples, languageTag = "it-IT").acceptedCandidate?.word
        }

        assertEquals("perché", recognize("perche"))
        assertEquals("l’ho", recognize("lho"))
        assertEquals("po’", recognize("po"))
    }

    @Test
    fun `canonical Italian vocabulary participates only in Italian swipe recognition`() {
        val source = File(
            repositoryRoot(),
            "android/app/src/main/res/raw/swipe_lexicon_it_v1.txt",
        ).readText()
        val engine = SwipeVocabulary.productionEngine(source)
        val samples = "ciao".mapIndexed { index, character ->
            val point = requireNotNull(QwertyKeyLayout.center(character))
            SwipePathSample(point.x, point.y, index * 100.0)
        }

        assertEquals("ciao", engine.recognize(samples, languageTag = "it-IT").acceptedCandidate?.word)
        assertTrue(engine.recognize(samples, languageTag = "en-US").candidates.none { it.word == "ciao" })

        val englishSamples = "the".mapIndexed { index, character ->
            val point = requireNotNull(QwertyKeyLayout.center(character))
            SwipePathSample(point.x, point.y, index * 100.0)
        }
        val englishResult = engine.recognize(englishSamples, languageTag = "en-US")
        assertEquals("the", englishResult.acceptedCandidate?.word)
        assertTrue(
            engine.recognize(englishSamples, languageTag = "it-IT")
                .candidates
                .none { it.word == "the" },
        )
    }

    private fun repositoryRoot(): File {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).canonicalFile
        repeat(8) {
            if (File(directory, "shared/keyboard-contract/v1").isDirectory) return directory
            directory = directory.parentFile
                ?: error("Could not locate repository root from ${System.getProperty("user.dir")}")
        }
        error("Could not locate repository root from ${System.getProperty("user.dir")}")
    }
}
