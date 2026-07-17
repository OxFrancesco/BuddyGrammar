package com.francescooddo.buddygrammar.core.adaptive

/**
 * Explicit, dependency-free persistence seam for [TypingProfileSnapshot].
 * The four-field format cannot contain typed text or individual tap samples.
 */
object TypingProfileCodec {
    fun encode(profile: TypingProfileSnapshot): String {
        val normalized = normalize(profile)
        return listOf(
            normalized.version,
            normalized.observationCount,
            normalized.meanOffsetX,
            normalized.meanOffsetY,
        ).joinToString(SEPARATOR)
    }

    fun decode(encoded: String?): TypingProfileSnapshot {
        val fields = encoded?.split(SEPARATOR) ?: return TypingProfileSnapshot()
        if (fields.size != FIELD_COUNT) return TypingProfileSnapshot()
        val profile = TypingProfileSnapshot(
            version = fields[0].toIntOrNull() ?: return TypingProfileSnapshot(),
            observationCount = fields[1].toIntOrNull() ?: return TypingProfileSnapshot(),
            meanOffsetX = fields[2].toDoubleOrNull() ?: return TypingProfileSnapshot(),
            meanOffsetY = fields[3].toDoubleOrNull() ?: return TypingProfileSnapshot(),
        )
        if (profile.version != TypingProfileSnapshot.CURRENT_PROFILE_VERSION) {
            return TypingProfileSnapshot()
        }
        return normalize(profile)
    }

    private fun normalize(profile: TypingProfileSnapshot): TypingProfileSnapshot {
        if (profile.version != TypingProfileSnapshot.CURRENT_PROFILE_VERSION) {
            return TypingProfileSnapshot()
        }
        return profile.copy(
            observationCount = profile.observationCount.coerceIn(0, MAX_OBSERVATIONS),
            meanOffsetX = profile.meanOffsetX.finiteOrZero().coerceIn(-MAX_ABS_OFFSET, MAX_ABS_OFFSET),
            meanOffsetY = profile.meanOffsetY.finiteOrZero().coerceIn(-MAX_ABS_OFFSET, MAX_ABS_OFFSET),
        )
    }

    private fun Double.finiteOrZero(): Double = if (isFinite()) this else 0.0

    private const val SEPARATOR = "|"
    private const val FIELD_COUNT = 4
    private const val MAX_OBSERVATIONS = 10_000
    private const val MAX_ABS_OFFSET = 0.50
}
