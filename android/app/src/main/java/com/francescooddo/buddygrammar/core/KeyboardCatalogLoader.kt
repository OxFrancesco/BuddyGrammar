package com.francescooddo.buddygrammar.core

import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

internal data class LoadedFieldVariant(
    val primaryPlane: CatalogPlane,
    val suggestions: SuggestionSurfaceMode,
    val inlineKeys: List<InlineCatalogKey>,
    val returnIntent: ReturnIntent,
    val usesLocaleDecimalSeparator: Boolean,
)

/** Validated, typed projection of the bundled keyboard contract. */
internal class LoadedKeyboardCatalog(
    val schemaVersion: Int,
    val revision: String,
    val gestures: KeyboardGestureConfiguration,
    private val defaultLanguageId: String,
    languages: List<KeyboardLanguagePack>,
    private val fieldVariants: Map<CatalogFieldKind, LoadedFieldVariant>,
) {
    private val languagesById = languages.associateBy(KeyboardLanguagePack::id)

    init {
        require(languagesById.size == languages.size) { "Keyboard catalog repeats a language id" }
        require(defaultLanguageId in languagesById) {
            "Keyboard catalog default language $defaultLanguageId does not exist"
        }
        require(fieldVariants.keys == CatalogFieldKind.entries.toSet()) {
            "Keyboard catalog must define every field kind exactly once"
        }
    }

    fun language(localeIdentifier: String?): KeyboardLanguagePack {
        val normalized = localeIdentifier.normalizedLocale()
        val base = normalized.substringBefore('-')
        return languagesById.values.firstOrNull { pack ->
            normalized in pack.localeAliases || base in pack.localeAliases
        } ?: requireNotNull(languagesById[defaultLanguageId])
    }

    fun presentation(
        fieldKind: CatalogFieldKind,
        localeIdentifier: String?,
    ): KeyboardFieldPresentation {
        val language = language(localeIdentifier)
        val variant = requireNotNull(fieldVariants[fieldKind])
        val inlineKeys = if (variant.usesLocaleDecimalSeparator) {
            variant.inlineKeys.map { key ->
                if (key.id == "decimal-separator") {
                    key.copy(
                        label = language.decimalSeparator,
                        output = language.decimalSeparator,
                    )
                } else {
                    key
                }
            }
        } else {
            variant.inlineKeys
        }
        return KeyboardFieldPresentation(
            fieldKind = fieldKind,
            language = language,
            primaryPlane = variant.primaryPlane,
            suggestions = variant.suggestions,
            inlineKeys = inlineKeys,
            returnIntent = variant.returnIntent,
        )
    }
}

/** Strict parser used by the production IME and JVM contract tests. */
internal object KeyboardCatalogLoader {
    fun parse(source: String): LoadedKeyboardCatalog {
        val root = JSONObject(source)
        val schemaVersion = root.getInt("schemaVersion")
        require(schemaVersion == SUPPORTED_SCHEMA_VERSION) {
            "Unsupported keyboard catalog schema $schemaVersion"
        }
        val revision = root.getString("catalogRevision").also {
            require(it.isNotBlank()) { "Keyboard catalog revision must not be blank" }
        }
        val profiles = parseProfiles(root.getJSONArray("layoutProfiles"))
        val fallbackProfileId = root.getString("fallbackLayoutProfileId")
        val fallbackProfile = profiles.firstOrNull { it.id == fallbackProfileId }
            ?: error("Keyboard catalog fallback profile $fallbackProfileId does not exist")
        val layouts = root.getJSONArray("layouts")
        val fallbackLayout = layouts.objects()
            .firstOrNull { it.getString("id") == fallbackProfile.layoutId }
            ?: error("Keyboard catalog fallback layout ${fallbackProfile.layoutId} does not exist")
        val languages = parseLanguages(root.getJSONArray("languages"), profiles)
        val fieldVariants = parseFieldVariants(fallbackLayout.getJSONArray("fieldVariants"))
        val gestures = parseGestures(root.getJSONObject("gestures"))

        return LoadedKeyboardCatalog(
            schemaVersion = schemaVersion,
            revision = revision,
            gestures = gestures,
            defaultLanguageId = root.getString("defaultLanguageId"),
            languages = languages,
            fieldVariants = fieldVariants,
        )
    }

    private fun parseProfiles(array: JSONArray): List<LayoutProfile> {
        val profiles = array.objects().map { profile ->
            val returnLabels = profile.getJSONObject("returnLabels")
            LayoutProfile(
                id = profile.getString("id"),
                layoutId = profile.getString("layoutId"),
                languageId = profile.getString("languageId"),
                spaceLabel = profile.getString("spaceLabel"),
                returnLabels = ReturnIntent.entries.associateWith { intent ->
                    returnLabels.getString(intent.jsonValue)
                },
            )
        }
        require(profiles.map(LayoutProfile::id).distinct().size == profiles.size) {
            "Keyboard catalog repeats a layout profile id"
        }
        return profiles
    }

    private fun parseLanguages(
        array: JSONArray,
        profiles: List<LayoutProfile>,
    ): List<KeyboardLanguagePack> = array.objects().map { language ->
        val id = language.getString("id")
        val profileId = language.getString("defaultLayoutProfileId")
        val profile = profiles.firstOrNull { it.id == profileId && it.languageId == id }
            ?: error("Language $id references invalid layout profile $profileId")
        val punctuation = language.getJSONObject("punctuation")
        KeyboardLanguagePack(
            id = id,
            localeAliases = language.getJSONArray("localeAliases")
                .strings()
                .map(String::normalizedLocale)
                .toSet(),
            spaceLabel = profile.spaceLabel,
            returnLabels = profile.returnLabels,
            decimalSeparator = punctuation.getString("decimalSeparator"),
            thousandsSeparator = punctuation.getString("thousandsSeparator"),
            alternates = parseAlternates(language.getJSONObject("alternates")),
        )
    }

    private fun parseAlternates(objectValue: JSONObject): Map<Char, List<String>> {
        val result = linkedMapOf<Char, List<String>>()
        val keys = objectValue.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            require(key.length == 1) { "Alternate key must be one character: $key" }
            result[key.single()] = objectValue.getJSONArray(key).strings()
        }
        return result
    }

    private fun parseFieldVariants(array: JSONArray): Map<CatalogFieldKind, LoadedFieldVariant> {
        val result = linkedMapOf<CatalogFieldKind, LoadedFieldVariant>()
        array.objects().forEach { variant ->
            val parsed = LoadedFieldVariant(
                primaryPlane = when (val value = variant.getString("primaryPlane")) {
                    "letters" -> CatalogPlane.LETTERS
                    "numbers" -> CatalogPlane.NUMBERS
                    else -> error("Unknown keyboard plane $value")
                },
                suggestions = when (val value = variant.getString("suggestionMode")) {
                    "full" -> SuggestionSurfaceMode.FULL
                    "localOnly" -> SuggestionSurfaceMode.LOCAL_ONLY
                    "off" -> SuggestionSurfaceMode.OFF
                    else -> error("Unknown suggestion mode $value")
                },
                inlineKeys = variant.getJSONArray("inlineKeys").objects().map { key ->
                    InlineCatalogKey(
                        id = key.getString("id"),
                        label = key.getString("label"),
                        output = key.getString("output"),
                    )
                },
                returnIntent = returnIntent(variant.getString("returnIntent")),
                usesLocaleDecimalSeparator = variant.optBoolean(
                    "usesLocaleDecimalSeparator",
                    false,
                ),
            )
            variant.getJSONArray("fieldKinds").strings().forEach { value ->
                val fieldKind = fieldKind(value)
                require(result.put(fieldKind, parsed) == null) {
                    "Keyboard catalog repeats field kind $value"
                }
            }
        }
        return result
    }

    private fun parseGestures(objectValue: JSONObject): KeyboardGestureConfiguration {
        val spaceCursor = objectValue.getJSONObject("spaceCursor")
        val deleteRepeat = objectValue.getJSONObject("deleteRepeat")
        return KeyboardGestureConfiguration(
            spaceCursorActivationMilliseconds =
                spaceCursor.positiveInt("activationMilliseconds"),
            cursorPointsPerGrapheme = spaceCursor.positiveInt("pointsPerGrapheme"),
            deleteInitialDelayMilliseconds =
                deleteRepeat.positiveInt("initialDelayMilliseconds"),
            deleteIntervalMilliseconds = deleteRepeat.positiveInt("intervalMilliseconds"),
        )
    }

    private fun fieldKind(value: String): CatalogFieldKind = when (value) {
        "text" -> CatalogFieldKind.TEXT
        "multiline" -> CatalogFieldKind.MULTILINE
        "literal" -> CatalogFieldKind.LITERAL
        "name" -> CatalogFieldKind.NAME
        "search" -> CatalogFieldKind.SEARCH
        "email" -> CatalogFieldKind.EMAIL
        "url" -> CatalogFieldKind.URL
        "number" -> CatalogFieldKind.NUMBER
        "decimal" -> CatalogFieldKind.DECIMAL
        "phone" -> CatalogFieldKind.PHONE
        "datetime" -> CatalogFieldKind.DATETIME
        "code" -> CatalogFieldKind.CODE
        "oneTimeCode" -> CatalogFieldKind.ONE_TIME_CODE
        "password" -> CatalogFieldKind.PASSWORD
        else -> error("Unknown keyboard field kind $value")
    }

    private fun returnIntent(value: String): ReturnIntent = ReturnIntent.entries
        .firstOrNull { it.jsonValue == value }
        ?: error("Unknown return intent $value")

    private fun JSONObject.positiveInt(name: String): Int = getInt(name).also { value ->
        require(value > 0) { "Keyboard catalog $name must be positive" }
    }

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map(::getJSONObject)

    private fun JSONArray.strings(): List<String> = (0 until length()).map(::getString)

    private val ReturnIntent.jsonValue: String get() = name.lowercase(Locale.ROOT)

    private data class LayoutProfile(
        val id: String,
        val layoutId: String,
        val languageId: String,
        val spaceLabel: String,
        val returnLabels: Map<ReturnIntent, String>,
    )

    private const val SUPPORTED_SCHEMA_VERSION = 1
}

private fun String?.normalizedLocale(): String = this
    ?.replace('_', '-')
    ?.trim()
    ?.lowercase(Locale.ROOT)
    .orEmpty()
