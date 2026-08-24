package com.francescooddo.buddygrammar.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardCatalogTest {
    @Test
    fun `locale aliases resolve before safe English fallback`() {
        assertEquals("it", KeyboardCatalog.language("it_CH").id)
        assertEquals("it", KeyboardCatalog.language("IT-it").id)
        assertEquals("en", KeyboardCatalog.language("fr-FR").id)
    }

    @Test
    fun `Italian pack owns punctuation alternates and labels`() {
        val italian = KeyboardCatalog.language("it-IT")

        assertEquals(",", italian.decimalSeparator)
        assertEquals("è", italian.alternates.getValue('e').first())
        assertEquals("spazio", italian.spaceLabel)
        assertEquals("cerca", italian.returnLabels.getValue(ReturnIntent.SEARCH))
    }

    @Test
    fun `field presentations expose purpose built keys`() {
        assertEquals(
            listOf("@", "."),
            KeyboardCatalog.presentation(CatalogFieldKind.EMAIL, "en-US")
                .inlineKeys.map(InlineCatalogKey::output),
        )
        assertEquals(
            listOf("/", ".", ".com"),
            KeyboardCatalog.presentation(CatalogFieldKind.URL, "en-US")
                .inlineKeys.map(InlineCatalogKey::output),
        )
        assertEquals(
            listOf(","),
            KeyboardCatalog.presentation(CatalogFieldKind.DECIMAL, "it-IT")
                .inlineKeys.map(InlineCatalogKey::output),
        )
        assertEquals(
            listOf("+", "#", "*"),
            KeyboardCatalog.presentation(CatalogFieldKind.PHONE, "it-IT")
                .inlineKeys.map(InlineCatalogKey::output),
        )
        assertEquals(
            SuggestionSurfaceMode.OFF,
            KeyboardCatalog.presentation(CatalogFieldKind.LITERAL, "en-US").suggestions,
        )
        assertTrue(
            KeyboardCatalog.presentation(CatalogFieldKind.LITERAL, "en-US").inlineKeys.isEmpty(),
        )
        assertEquals(
            listOf("_", "/", "-"),
            KeyboardCatalog.presentation(CatalogFieldKind.CODE, "en-US")
                .inlineKeys.map(InlineCatalogKey::output),
        )
    }

    @Test
    fun `published gesture thresholds configure native routing`() {
        assertEquals(180, KeyboardCatalog.gestures.spaceCursorActivationMilliseconds)
        assertEquals(12, KeyboardCatalog.gestures.cursorPointsPerGrapheme)
        assertEquals(360, KeyboardCatalog.gestures.deleteInitialDelayMilliseconds)
        assertEquals(70, KeyboardCatalog.gestures.deleteIntervalMilliseconds)
    }

    @Test
    fun `bundled production catalog drives typed language field and gesture projections`() {
        val source = File(
            repositoryRoot(),
            "android/app/src/main/res/raw/keyboard_catalog.json",
        ).readText()

        KeyboardCatalog.resetToFallbackForTests()
        try {
            assertTrue(KeyboardCatalog.installBundled(source).isSuccess)
            assertEquals(1, KeyboardCatalog.SCHEMA_VERSION)
            assertEquals("2026.07.1", KeyboardCatalog.REVISION)
            assertEquals("spazio", KeyboardCatalog.language("it-CH").spaceLabel)
            assertEquals(
                listOf(","),
                KeyboardCatalog.presentation(CatalogFieldKind.DECIMAL, "it-IT")
                    .inlineKeys.map(InlineCatalogKey::output),
            )
            assertEquals(180, KeyboardCatalog.gestures.spaceCursorActivationMilliseconds)
        } finally {
            KeyboardCatalog.resetToFallbackForTests()
        }
    }

    @Test
    fun `malformed or unsupported bundled catalog activates safe literal fallback`() {
        KeyboardCatalog.resetToFallbackForTests()
        try {
            val result = KeyboardCatalog.installBundled(
                """{"schemaVersion":99,"catalogRevision":"future"}""",
            )

            assertTrue(result.isFailure)
            assertTrue(KeyboardCatalog.isUsingFallback)
            assertEquals("en", KeyboardCatalog.language("unknown").id)
            assertEquals(360, KeyboardCatalog.gestures.deleteInitialDelayMilliseconds)
        } finally {
            KeyboardCatalog.resetToFallbackForTests()
        }
    }

    private fun repositoryRoot(): File {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).canonicalFile
        repeat(8) {
            if (File(directory, "shared/keyboard-contract/v1").isDirectory) return directory
            directory = directory.parentFile
                ?: error("Could not locate repository root from user.dir")
        }
        error("Could not locate repository root from user.dir")
    }
}
