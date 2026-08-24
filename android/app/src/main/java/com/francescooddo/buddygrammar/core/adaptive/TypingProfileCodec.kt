package com.francescooddo.buddygrammar.core.adaptive

/**
 * Explicit, dependency-free persistence seam for [TypingProfileSnapshot].
 * The format contains only bounded global/per-key aggregates. It cannot hold
 * typed text, timestamps, or individual tap samples.
 */
object TypingProfileCodec {
    fun encode(profile: TypingProfileSnapshot): String {
        val normalized = normalize(profile)
        return listOf(
            normalized.version,
            normalized.observationCount,
            normalized.meanOffsetX,
            normalized.meanOffsetY,
            normalized.keyOffsets
                .toSortedMap()
                .entries
                .joinToString(KEY_SEPARATOR) { (key, aggregate) ->
                    listOf(
                        key,
                        aggregate.observationCount,
                        aggregate.meanOffsetX,
                        aggregate.meanOffsetY,
                    ).joinToString(KEY_FIELD_SEPARATOR)
                },
        ).joinToString(SEPARATOR)
    }

    fun decode(encoded: String?): TypingProfileSnapshot {
        val fields = encoded?.split(SEPARATOR) ?: return TypingProfileSnapshot()
        return when (fields.firstOrNull()?.toIntOrNull()) {
            LEGACY_PROFILE_VERSION -> decodeLegacy(fields)
            TypingProfileSnapshot.CURRENT_PROFILE_VERSION -> decodeCurrent(fields)
            else -> TypingProfileSnapshot()
        }
    }

    private fun decodeLegacy(fields: List<String>): TypingProfileSnapshot {
        if (fields.size != LEGACY_FIELD_COUNT) return TypingProfileSnapshot()
        return normalize(
            TypingProfileSnapshot(
                observationCount = fields[1].toIntOrNull() ?: return TypingProfileSnapshot(),
                meanOffsetX = fields[2].toDoubleOrNull() ?: return TypingProfileSnapshot(),
                meanOffsetY = fields[3].toDoubleOrNull() ?: return TypingProfileSnapshot(),
            ),
        )
    }

    private fun decodeCurrent(fields: List<String>): TypingProfileSnapshot {
        if (fields.size != CURRENT_FIELD_COUNT) return TypingProfileSnapshot()
        val keyOffsets = if (fields[4].isEmpty()) {
            emptyMap()
        } else {
            fields[4]
                .split(KEY_SEPARATOR)
                .mapNotNull { encodedAggregate ->
                    val parts = encodedAggregate.split(KEY_FIELD_SEPARATOR)
                    if (parts.size != KEY_FIELD_COUNT) return@mapNotNull null
                    val key = parts[0].singleOrNull()?.lowercaseChar()?.toString()
                        ?: return@mapNotNull null
                    key to KeyOffsetAggregate(
                        observationCount = parts[1].toIntOrNull() ?: return@mapNotNull null,
                        meanOffsetX = parts[2].toDoubleOrNull() ?: return@mapNotNull null,
                        meanOffsetY = parts[3].toDoubleOrNull() ?: return@mapNotNull null,
                    )
                }
                .toMap()
        }
        return normalize(
            TypingProfileSnapshot(
                observationCount = fields[1].toIntOrNull() ?: return TypingProfileSnapshot(),
                meanOffsetX = fields[2].toDoubleOrNull() ?: return TypingProfileSnapshot(),
                meanOffsetY = fields[3].toDoubleOrNull() ?: return TypingProfileSnapshot(),
                keyOffsets = keyOffsets,
            ),
        )
    }

    private fun normalize(profile: TypingProfileSnapshot): TypingProfileSnapshot {
        if (profile.version != TypingProfileSnapshot.CURRENT_PROFILE_VERSION) {
            return TypingProfileSnapshot()
        }
        return profile.copy(
            observationCount = profile.observationCount.coerceIn(0, MAX_OBSERVATIONS),
            meanOffsetX = profile.meanOffsetX.finiteOrZero().coerceIn(-MAX_ABS_OFFSET, MAX_ABS_OFFSET),
            meanOffsetY = profile.meanOffsetY.finiteOrZero().coerceIn(-MAX_ABS_OFFSET, MAX_ABS_OFFSET),
            keyOffsets = profile.keyOffsets
                .mapNotNull { (key, aggregate) ->
                    key.singleOrNull()
                        ?.lowercaseChar()
                        ?.takeIf { it in 'a'..'z' }
                        ?.toString()
                        ?.let { normalizedKey ->
                            normalizedKey to aggregate.copy(
                                observationCount = aggregate.observationCount
                                    .coerceIn(0, MAX_KEY_OBSERVATIONS),
                                meanOffsetX = aggregate.meanOffsetX.finiteOrZero()
                                    .coerceIn(-MAX_ABS_OFFSET, MAX_ABS_OFFSET),
                                meanOffsetY = aggregate.meanOffsetY.finiteOrZero()
                                    .coerceIn(-MAX_ABS_OFFSET, MAX_ABS_OFFSET),
                            )
                        }
                }
                .toMap(),
        )
    }

    private fun Double.finiteOrZero(): Double = if (isFinite()) this else 0.0

    private const val SEPARATOR = "|"
    private const val KEY_SEPARATOR = ";"
    private const val KEY_FIELD_SEPARATOR = ","
    private const val KEY_FIELD_COUNT = 4
    private const val LEGACY_PROFILE_VERSION = 1
    private const val LEGACY_FIELD_COUNT = 4
    private const val CURRENT_FIELD_COUNT = 5
    private const val MAX_OBSERVATIONS = 10_000
    private const val MAX_KEY_OBSERVATIONS = 512
    private const val MAX_ABS_OFFSET = 0.50
}
