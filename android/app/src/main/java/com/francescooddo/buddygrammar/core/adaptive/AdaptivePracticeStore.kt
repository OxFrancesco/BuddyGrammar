package com.francescooddo.buddygrammar.core.adaptive

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class ActivePracticeSession(
    val promptId: String,
    val expectedText: String,
    val startedAtEpochMillis: Long,
    val expiresAtEpochMillis: Long,
)

/**
 * Local persistence for aggregate practice state.
 *
 * The stored schema deliberately has no prompt, response, or decoded-text fields.
 */
class AdaptivePracticeStore internal constructor(
    private val readPayload: () -> String?,
    private val writePayload: (String?) -> Unit,
    private val readSessionPayload: () -> String? = { null },
    private val writeSessionPayload: (String?) -> Unit = {},
) {
    constructor(context: Context) : this(
        readPayload = {
            context.applicationContext
                .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(PROFILE_KEY, null)
        },
        writePayload = { payload ->
            val editor = context.applicationContext
                .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
            if (payload == null) editor.remove(PROFILE_KEY) else editor.putString(PROFILE_KEY, payload)
            editor.apply()
        },
        readSessionPayload = {
            context.applicationContext
                .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(SESSION_KEY, null)
        },
        writeSessionPayload = { payload ->
            val editor = context.applicationContext
                .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
            if (payload == null) editor.remove(SESSION_KEY) else editor.putString(SESSION_KEY, payload)
            editor.apply()
        },
    )

    fun load(): PracticeProfile = runCatching {
        decodeProfile(readPayload())
    }.getOrDefault(PracticeProfile())

    fun save(profile: PracticeProfile) {
        writePayload(encodeProfile(profile))
    }

    fun reset() {
        writePayload(null)
        writeSessionPayload(null)
    }

    fun saveActiveSession(session: ActivePracticeSession) {
        val normalized = session.copy(
            promptId = session.promptId.trim().take(MAX_IDENTIFIER_LENGTH),
            expectedText = session.expectedText.take(MAX_EXPECTED_TEXT_LENGTH),
            startedAtEpochMillis = session.startedAtEpochMillis.coerceAtLeast(0L),
            expiresAtEpochMillis = session.expiresAtEpochMillis.coerceAtLeast(0L),
        )
        if (
            normalized.promptId.isEmpty() ||
            normalized.expectedText.isEmpty() ||
            normalized.expiresAtEpochMillis <= normalized.startedAtEpochMillis
        ) {
            clearActiveSession()
            return
        }
        writeSessionPayload(
            JSONObject()
                .put("version", SESSION_SCHEMA_VERSION)
                .put("promptId", normalized.promptId)
                .put("expectedText", normalized.expectedText)
                .put("startedAtEpochMillis", normalized.startedAtEpochMillis)
                .put("expiresAtEpochMillis", normalized.expiresAtEpochMillis)
                .toString(),
        )
    }

    fun loadActiveSession(
        nowEpochMillis: Long = System.currentTimeMillis(),
    ): ActivePracticeSession? {
        val payload = readSessionPayload()
        if (payload.isNullOrBlank()) return null
        val session = runCatching { decodeActiveSession(payload) }.getOrNull()
        if (session == null || nowEpochMillis >= session.expiresAtEpochMillis) {
            clearActiveSession()
            return null
        }
        return session
    }

    fun clearActiveSession() {
        writeSessionPayload(null)
    }

    private fun decodeActiveSession(payload: String): ActivePracticeSession? {
        val value = JSONObject(payload)
        if (value.optInt("version", -1) != SESSION_SCHEMA_VERSION) return null
        val promptId = value.optString("promptId").trim().take(MAX_IDENTIFIER_LENGTH)
        val expectedText = value.optString("expectedText").take(MAX_EXPECTED_TEXT_LENGTH)
        val startedAt = value.optLong("startedAtEpochMillis", -1L)
        val expiresAt = value.optLong("expiresAtEpochMillis", -1L)
        if (promptId.isEmpty() || expectedText.isEmpty() || startedAt < 0L || expiresAt <= startedAt) {
            return null
        }
        return ActivePracticeSession(
            promptId = promptId,
            expectedText = expectedText,
            startedAtEpochMillis = startedAt,
            expiresAtEpochMillis = expiresAt,
        )
    }

    private fun encodeProfile(profile: PracticeProfile): String = JSONObject()
        .put("version", SCHEMA_VERSION)
        .put("completedAttempts", profile.completedAttempts.coerceAtLeast(0))
        .put("abandonedAttempts", profile.abandonedAttempts.coerceAtLeast(0))
        .put("meanRawAccuracy", profile.meanRawAccuracy.safeUnitValue())
        .put("meanDecodedAccuracy", profile.meanDecodedAccuracy.safeUnitValue())
        .put(
            "skills",
            JSONArray().also { array ->
                profile.skills.values
                    .sortedBy(PracticeSkillState::id)
                    .forEach { skill -> array.put(encodeSkill(skill)) }
            },
        )
        .put(
            "items",
            JSONArray().also { array ->
                profile.items.values
                    .sortedBy(PracticeItemState::id)
                    .forEach { item -> array.put(encodeItem(item)) }
            },
        )
        .toString()

    private fun encodeSkill(skill: PracticeSkillState): JSONObject = JSONObject()
        .put("id", skill.id)
        .put("family", skill.family.name)
        .put("observations", skill.observations.coerceAtLeast(0))
        .put("weightedSuccesses", skill.weightedSuccesses.safePositiveValue())
        .put("weightedFailures", skill.weightedFailures.safePositiveValue())
        .put("mastery", skill.mastery.safeUnitValue())
        .put("uncertainty", skill.uncertainty.safeUnitValue())
        .put("halfLifeDays", skill.halfLifeDays.safePositiveValue())
        .also { objectValue ->
            skill.lastObservedAtEpochMillis?.let {
                objectValue.put("lastObservedAtEpochMillis", it.coerceAtLeast(0L))
            }
        }
        .put(
            "retentionSchedule",
            JSONArray().also { array ->
                skill.retentionSchedule.forEach { checkpoint ->
                    array.put(
                        JSONObject()
                            .put("day", checkpoint.day.coerceAtLeast(0))
                            .put("dueAtEpochMillis", checkpoint.dueAtEpochMillis.coerceAtLeast(0L)),
                    )
                }
            },
        )

    private fun encodeItem(item: PracticeItemState): JSONObject = JSONObject()
        .put("id", item.id)
        .put("exposures", item.exposures.coerceAtLeast(0))
        .also { objectValue ->
            item.lastPresentedAtEpochMillis?.let {
                objectValue.put("lastPresentedAtEpochMillis", it.coerceAtLeast(0L))
            }
        }

    private fun decodeProfile(payload: String?): PracticeProfile {
        if (payload.isNullOrBlank()) return PracticeProfile()
        val root = JSONObject(payload)
        if (root.optInt("version", -1) != SCHEMA_VERSION) return PracticeProfile()

        val skills = buildMap {
            val values = root.optJSONArray("skills") ?: JSONArray()
            for (index in 0 until minOf(values.length(), MAX_SKILLS)) {
                decodeSkill(values.optJSONObject(index) ?: continue)?.let { put(it.id, it) }
            }
        }
        val items = buildMap {
            val values = root.optJSONArray("items") ?: JSONArray()
            for (index in 0 until minOf(values.length(), MAX_ITEMS)) {
                decodeItem(values.optJSONObject(index) ?: continue)?.let { put(it.id, it) }
            }
        }
        return PracticeProfile(
            skills = skills,
            items = items,
            completedAttempts = root.optInt("completedAttempts", 0).coerceIn(0, MAX_ATTEMPTS),
            abandonedAttempts = root.optInt("abandonedAttempts", 0).coerceIn(0, MAX_ATTEMPTS),
            meanRawAccuracy = root.optDouble("meanRawAccuracy", 0.0).safeUnitValue(),
            meanDecodedAccuracy = root.optDouble("meanDecodedAccuracy", 0.0).safeUnitValue(),
        )
    }

    private fun decodeSkill(value: JSONObject): PracticeSkillState? {
        val id = value.optString("id").trim().takeIf { it.isNotEmpty() } ?: return null
        val family = runCatching {
            PracticeSkillFamily.valueOf(value.optString("family"))
        }.getOrNull() ?: return null
        val retention = buildList {
            val values = value.optJSONArray("retentionSchedule") ?: JSONArray()
            for (index in 0 until minOf(values.length(), MAX_CHECKPOINTS)) {
                val checkpoint = values.optJSONObject(index) ?: continue
                add(
                    PracticeRetentionCheckpoint(
                        day = checkpoint.optInt("day", 0).coerceAtLeast(0),
                        dueAtEpochMillis = checkpoint.optLong("dueAtEpochMillis", 0L)
                            .coerceAtLeast(0L),
                    ),
                )
            }
        }
        return PracticeSkillState(
            id = id.take(MAX_IDENTIFIER_LENGTH),
            family = family,
            observations = value.optInt("observations", 0).coerceIn(0, MAX_ATTEMPTS),
            weightedSuccesses = value.optDouble("weightedSuccesses", 0.0).safePositiveValue(),
            weightedFailures = value.optDouble("weightedFailures", 0.0).safePositiveValue(),
            mastery = value.optDouble("mastery", 0.5).safeUnitValue(),
            uncertainty = value.optDouble("uncertainty", 1.0).safeUnitValue(),
            halfLifeDays = value.optDouble("halfLifeDays", 1.0).safePositiveValue()
                .coerceIn(MIN_HALF_LIFE_DAYS, MAX_HALF_LIFE_DAYS),
            lastObservedAtEpochMillis = value.optionalLong("lastObservedAtEpochMillis"),
            retentionSchedule = retention,
        )
    }

    private fun decodeItem(value: JSONObject): PracticeItemState? {
        val id = value.optString("id").trim().takeIf { it.isNotEmpty() } ?: return null
        return PracticeItemState(
            id = id.take(MAX_IDENTIFIER_LENGTH),
            exposures = value.optInt("exposures", 0).coerceIn(0, MAX_ATTEMPTS),
            lastPresentedAtEpochMillis = value.optionalLong("lastPresentedAtEpochMillis"),
        )
    }

    private fun JSONObject.optionalLong(key: String): Long? = if (has(key) && !isNull(key)) {
        optLong(key, 0L).coerceAtLeast(0L)
    } else {
        null
    }

    private fun Double.safeUnitValue(): Double = if (isFinite()) coerceIn(0.0, 1.0) else 0.0

    private fun Double.safePositiveValue(): Double = if (isFinite()) coerceAtLeast(0.0) else 0.0

    private companion object {
        const val PREFERENCES_NAME = "buddygrammar_shared"
        const val PROFILE_KEY = "adaptive.practice.v1"
        const val SESSION_KEY = "adaptive.practice.session.v1"
        const val SCHEMA_VERSION = 1
        const val SESSION_SCHEMA_VERSION = 1
        const val MAX_ATTEMPTS = 1_000_000
        const val MAX_SKILLS = 512
        const val MAX_ITEMS = 512
        const val MAX_CHECKPOINTS = 12
        const val MAX_IDENTIFIER_LENGTH = 128
        const val MAX_EXPECTED_TEXT_LENGTH = 500
        const val MIN_HALF_LIFE_DAYS = 0.25
        const val MAX_HALF_LIFE_DAYS = 365.0
    }
}
