package com.francescooddo.buddygrammar.core

import java.util.Locale

enum class CatalogFieldKind {
    TEXT,
    MULTILINE,
    LITERAL,
    NAME,
    SEARCH,
    EMAIL,
    URL,
    NUMBER,
    DECIMAL,
    PHONE,
    DATETIME,
    CODE,
    ONE_TIME_CODE,
    PASSWORD,
}

enum class CatalogPlane { LETTERS, NUMBERS }

enum class ReturnIntent { NEWLINE, DONE, GO, NEXT, SEARCH, SEND }

data class InlineCatalogKey(
    val id: String,
    val label: String,
    val output: String,
)

data class KeyboardLanguagePack(
    val id: String,
    val localeAliases: Set<String>,
    val spaceLabel: String,
    val returnLabels: Map<ReturnIntent, String>,
    val decimalSeparator: String,
    val thousandsSeparator: String,
    val alternates: Map<Char, List<String>>,
)

data class KeyboardFieldPresentation(
    val fieldKind: CatalogFieldKind,
    val language: KeyboardLanguagePack,
    val primaryPlane: CatalogPlane,
    val suggestions: SuggestionSurfaceMode,
    val inlineKeys: List<InlineCatalogKey>,
    val returnIntent: ReturnIntent,
)

enum class SuggestionSurfaceMode { FULL, LOCAL_ONLY, OFF }

data class KeyboardGestureConfiguration(
    val spaceCursorActivationMilliseconds: Int,
    val cursorPointsPerGrapheme: Int,
    val deleteInitialDelayMilliseconds: Int,
    val deleteIntervalMilliseconds: Int,
) {
    fun routerConfiguration() = KeyboardInteractionRouter.Configuration(
        cursorActivationDelaySeconds = spaceCursorActivationMilliseconds / 1_000.0,
        cursorActivationDistance = cursorPointsPerGrapheme.toDouble(),
        cursorStep = cursorPointsPerGrapheme.toDouble(),
        deleteRepeatDelaySeconds = deleteInitialDelayMilliseconds / 1_000.0,
        deleteRepeatIntervalSeconds = deleteIntervalMilliseconds / 1_000.0,
        minimumDeleteRepeatIntervalSeconds = deleteIntervalMilliseconds / 1_000.0,
    )
}

/**
 * Runtime projection of shared/keyboard-contract/v1/catalog.json.
 *
 * The production IME installs the bundled JSON once during service startup.
 * The literal data below is a safe, reviewable fallback for a malformed or
 * unsupported bundle; key interaction never parses JSON on the hot path.
 */
object KeyboardCatalog {
    private const val FALLBACK_SCHEMA_VERSION = 1
    private const val FALLBACK_REVISION = "2026.07.1"

    @Volatile
    private var loadedCatalog: LoadedKeyboardCatalog? = null

    val SCHEMA_VERSION: Int get() = loadedCatalog?.schemaVersion ?: FALLBACK_SCHEMA_VERSION
    val REVISION: String get() = loadedCatalog?.revision ?: FALLBACK_REVISION
    val isUsingFallback: Boolean get() = loadedCatalog == null

    private val fallbackGestures = KeyboardGestureConfiguration(
        spaceCursorActivationMilliseconds = 180,
        cursorPointsPerGrapheme = 12,
        deleteInitialDelayMilliseconds = 360,
        deleteIntervalMilliseconds = 70,
    )
    val gestures: KeyboardGestureConfiguration
        get() = loadedCatalog?.gestures ?: fallbackGestures

    private val english = KeyboardLanguagePack(
        id = "en",
        localeAliases = setOf("en", "en-us", "en-gb", "en-ca", "en-au", "en-ie"),
        spaceLabel = "space",
        returnLabels = mapOf(
            ReturnIntent.NEWLINE to "return",
            ReturnIntent.DONE to "done",
            ReturnIntent.GO to "go",
            ReturnIntent.NEXT to "next",
            ReturnIntent.SEARCH to "search",
            ReturnIntent.SEND to "send",
        ),
        decimalSeparator = ".",
        thousandsSeparator = ",",
        alternates = mapOf(
            'a' to listOf("á", "à", "â", "ä", "æ", "ã", "å"),
            'c' to listOf("ç"),
            'e' to listOf("é", "è", "ê", "ë"),
            'i' to listOf("í", "ì", "î", "ï"),
            'n' to listOf("ñ"),
            'o' to listOf("ó", "ò", "ô", "ö", "œ", "õ", "ø"),
            's' to listOf("ß"),
            'u' to listOf("ú", "ù", "û", "ü"),
            'y' to listOf("ý", "ÿ"),
        ),
    )

    private val italian = KeyboardLanguagePack(
        id = "it",
        localeAliases = setOf("it", "it-it", "it-ch", "it-sm", "it-va"),
        spaceLabel = "spazio",
        returnLabels = mapOf(
            ReturnIntent.NEWLINE to "invio",
            ReturnIntent.DONE to "fine",
            ReturnIntent.GO to "vai",
            ReturnIntent.NEXT to "avanti",
            ReturnIntent.SEARCH to "cerca",
            ReturnIntent.SEND to "invia",
        ),
        decimalSeparator = ",",
        thousandsSeparator = ".",
        alternates = mapOf(
            'a' to listOf("à", "á", "â", "ä"),
            'c' to listOf("ç"),
            'e' to listOf("è", "é", "ê", "ë"),
            'i' to listOf("ì", "í", "î", "ï"),
            'o' to listOf("ò", "ó", "ô", "ö"),
            'u' to listOf("ù", "ú", "û", "ü"),
        ),
    )

    private val fallbackLanguages = listOf(english, italian)

    /** Installs validated bundled data, or resets to the literal safe fallback. */
    fun installBundled(source: String): Result<Unit> {
        val parsed = runCatching { KeyboardCatalogLoader.parse(source) }
        return parsed.fold(
            onSuccess = { catalog ->
                loadedCatalog = catalog
                Result.success(Unit)
            },
            onFailure = { error ->
                loadedCatalog = null
                Result.failure(error)
            },
        )
    }

    internal fun resetToFallbackForTests() {
        loadedCatalog = null
    }

    fun language(localeIdentifier: String?): KeyboardLanguagePack {
        loadedCatalog?.let { return it.language(localeIdentifier) }
        val normalized = localeIdentifier
            ?.replace('_', '-')
            ?.trim()
            ?.lowercase(Locale.ROOT)
            .orEmpty()
        val base = normalized.substringBefore('-')
        return fallbackLanguages.firstOrNull { pack ->
            normalized in pack.localeAliases || base in pack.localeAliases
        } ?: english
    }

    fun presentation(
        fieldKind: CatalogFieldKind,
        localeIdentifier: String?,
    ): KeyboardFieldPresentation {
        loadedCatalog?.let { return it.presentation(fieldKind, localeIdentifier) }
        val language = language(localeIdentifier)
        val primaryPlane = when (fieldKind) {
            CatalogFieldKind.NUMBER,
            CatalogFieldKind.DECIMAL,
            CatalogFieldKind.PHONE,
            CatalogFieldKind.DATETIME,
            -> CatalogPlane.NUMBERS
            else -> CatalogPlane.LETTERS
        }
        val suggestions = when (fieldKind) {
            CatalogFieldKind.TEXT,
            CatalogFieldKind.MULTILINE,
            CatalogFieldKind.NAME,
            -> SuggestionSurfaceMode.FULL
            CatalogFieldKind.SEARCH -> SuggestionSurfaceMode.LOCAL_ONLY
            else -> SuggestionSurfaceMode.OFF
        }
        val inlineKeys = when (fieldKind) {
            CatalogFieldKind.EMAIL -> listOf(key("at", "@"), key("period", "."))
            CatalogFieldKind.URL -> listOf(
                key("slash", "/"),
                key("period", "."),
                key("dot-com", ".com"),
            )
            CatalogFieldKind.DECIMAL -> listOf(
                key("decimal-separator", language.decimalSeparator),
            )
            CatalogFieldKind.PHONE -> listOf(
                key("plus", "+"),
                key("hash", "#"),
                key("asterisk", "*"),
            )
            CatalogFieldKind.CODE -> listOf(
                key("underscore", "_"),
                key("slash", "/"),
                key("dash", "-"),
            )
            else -> emptyList()
        }
        val returnIntent = when (fieldKind) {
            CatalogFieldKind.SEARCH -> ReturnIntent.SEARCH
            CatalogFieldKind.URL -> ReturnIntent.GO
            CatalogFieldKind.EMAIL -> ReturnIntent.NEXT
            CatalogFieldKind.TEXT,
            CatalogFieldKind.MULTILINE,
            CatalogFieldKind.NAME,
            CatalogFieldKind.CODE,
            CatalogFieldKind.LITERAL,
            -> ReturnIntent.NEWLINE
            else -> ReturnIntent.DONE
        }
        return KeyboardFieldPresentation(
            fieldKind = fieldKind,
            language = language,
            primaryPlane = primaryPlane,
            suggestions = suggestions,
            inlineKeys = inlineKeys,
            returnIntent = returnIntent,
        )
    }

    private fun key(id: String, output: String) = InlineCatalogKey(id, output, output)
}
