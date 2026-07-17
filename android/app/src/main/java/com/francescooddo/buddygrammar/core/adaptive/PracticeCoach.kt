package com.francescooddo.buddygrammar.core.adaptive

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

enum class PracticeKind {
    COPY,
    CLOZE,
    CORRECTION,
    RECONSTRUCTION,
    FREE_PRODUCTION,
    MIXED_TRANSFER,
}

enum class PracticeTrack {
    MOTOR,
    WRITING,
    MIXED,
}

data class PracticeRequest(
    val track: PracticeTrack = PracticeTrack.MIXED,
    val preferredKinds: Set<PracticeKind> = emptySet(),
    val goalSkillIds: Set<String> = emptySet(),
    val retentionDay: Int? = null,
)

data class PracticePrompt(
    val id: String,
    val kind: PracticeKind,
    val track: PracticeTrack,
    val instruction: String,
    val stimulus: String? = null,
    val expectedText: String,
    val motorTarget: String? = null,
    val skillIds: Set<String>,
    val isHoldout: Boolean = false,
)

enum class PracticeAssistance {
    NONE,
    ADAPTIVE_KEYBOARD,
    SUGGESTION,
    CORRECTION,
    COPIED,
}

data class PracticeAttempt(
    val prompt: PracticePrompt,
    val rawText: String,
    val decodedText: String = rawText,
    val assistance: PracticeAssistance = PracticeAssistance.NONE,
    val abandoned: Boolean = false,
)

enum class PracticeRecordStatus {
    RECORDED,
    ABANDONED,
    HOLDOUT,
}

data class PracticeResult(
    val status: PracticeRecordStatus,
    val rawAccuracy: Double,
    val decodedAccuracy: Double,
    val evidenceWeight: Double,
    val updatedSkillIds: Set<String>,
)

enum class PracticeSkillFamily {
    MOTOR,
    WRITING,
}

data class PracticeRetentionCheckpoint(
    val day: Int,
    val dueAtEpochMillis: Long,
)

data class PracticeSkillState(
    val id: String,
    val family: PracticeSkillFamily,
    val observations: Int = 0,
    val weightedSuccesses: Double = 0.0,
    val weightedFailures: Double = 0.0,
    val mastery: Double = 0.5,
    val uncertainty: Double = 1.0,
    val halfLifeDays: Double = 1.0,
    val lastObservedAtEpochMillis: Long? = null,
    val retentionSchedule: List<PracticeRetentionCheckpoint> = emptyList(),
)

data class PracticeItemState(
    val id: String,
    val exposures: Int = 0,
    val lastPresentedAtEpochMillis: Long? = null,
)

data class PracticeProfile(
    val skills: Map<String, PracticeSkillState> = emptyMap(),
    val items: Map<String, PracticeItemState> = emptyMap(),
    val completedAttempts: Int = 0,
    val abandonedAttempts: Int = 0,
    val meanRawAccuracy: Double = 0.0,
    val meanDecodedAccuracy: Double = 0.0,
)

class PracticeCoach(
    initialProfile: PracticeProfile = PracticeProfile(),
) {
    private data class BankItem(
        val prompt: PracticePrompt,
        val frequency: Double,
        val retentionDay: Int? = null,
    )

    private data class TargetObservation(
        val matches: Boolean,
        val responseIndex: Int?,
    )

    private data class Alignment(
        val accuracy: Double,
        val targetObservations: List<TargetObservation>,
    )

    private data class SkillEvidence(
        val family: PracticeSkillFamily,
        val score: Double,
    )

    private var profile = initialProfile

    fun snapshot(): PracticeProfile = profile

    fun nextPrompt(
        request: PracticeRequest = PracticeRequest(),
        nowEpochMillis: Long,
    ): PracticePrompt {
        request.retentionDay?.takeIf { it in RETENTION_DAYS }?.let { day ->
            holdoutItems.firstOrNull { item ->
                item.retentionDay == day && matches(request.track, item.prompt)
            }?.let { return it.prompt }
        }
        val trackCandidates = trainingItems.filter { item ->
            matches(request.track, item.prompt)
        }
        val preferredCandidates = trackCandidates.filter { item ->
            request.preferredKinds.isEmpty() || item.prompt.kind in request.preferredKinds
        }
        val candidates = preferredCandidates.ifEmpty { trackCandidates }
        return candidates.sortedWith(
            compareByDescending<BankItem> { item -> selectionScore(item, request, nowEpochMillis) }
                .thenBy { item -> item.prompt.id },
        ).firstOrNull()?.prompt ?: trainingItems.first().prompt
    }

    private fun selectionScore(
        item: BankItem,
        request: PracticeRequest,
        nowEpochMillis: Long,
    ): Double {
        val priorities = item.prompt.skillIds.map { id ->
            val state = profile.skills[id] ?: PracticeSkillState(
                id = id,
                family = family(id, item.prompt),
            )
            val goalImpact = if (id in request.goalSkillIds) 1.8 else 1.0
            priority(state, nowEpochMillis, item.frequency, goalImpact)
        }
        val learningPriority = if (priorities.isEmpty()) {
            0.4 * item.frequency
        } else {
            priorities.average()
        }
        val exposure = profile.items[item.prompt.id]?.exposures ?: 0
        val coverage = 1.0 / (1.0 + exposure)
        return learningPriority * coverage
    }

    private fun priority(
        state: PracticeSkillState,
        nowEpochMillis: Long,
        frequency: Double,
        goalImpact: Double,
    ): Double {
        val lastObserved = state.lastObservedAtEpochMillis
            ?: return 0.4 * state.uncertainty * frequency * goalImpact
        val elapsedDays = max(0L, nowEpochMillis - lastObserved).toDouble() / DAY_MILLIS.toDouble()
        val predictedRecall = 2.0.pow(-elapsedDays / max(0.25, state.halfLifeDays))
        val forgettingRisk = max(1.0 - predictedRecall, 1.0 - state.mastery)
        return forgettingRisk * state.uncertainty * frequency * goalImpact
    }

    fun record(
        attempt: PracticeAttempt,
        nowEpochMillis: Long,
    ): PracticeResult {
        val rawAlignment = align(attempt.prompt.expectedText, attempt.rawText)
        val decodedAlignment = align(attempt.prompt.expectedText, attempt.decodedText)
        if (attempt.prompt.isHoldout || attempt.prompt.id in holdoutIds) {
            return PracticeResult(
                status = PracticeRecordStatus.HOLDOUT,
                rawAccuracy = rawAlignment.accuracy,
                decodedAccuracy = decodedAlignment.accuracy,
                evidenceWeight = 0.0,
                updatedSkillIds = emptySet(),
            )
        }
        if (attempt.abandoned) {
            profile = profile.copy(
                items = exposedItems(attempt.prompt.id, nowEpochMillis),
                abandonedAttempts = profile.abandonedAttempts + 1,
            )
            return PracticeResult(
                status = PracticeRecordStatus.ABANDONED,
                rawAccuracy = rawAlignment.accuracy,
                decodedAccuracy = decodedAlignment.accuracy,
                evidenceWeight = 0.0,
                updatedSkillIds = emptySet(),
            )
        }
        val evidence = staticEvidence(
            attempt.prompt,
            rawAlignment.accuracy,
            decodedAlignment.accuracy,
        ).toMutableMap()
        attempt.prompt.motorTarget?.let { target ->
            motorEvidence(target, align(target, attempt.rawText)).forEach { (id, score) ->
                evidence[id] = SkillEvidence(PracticeSkillFamily.MOTOR, score)
            }
        }
        val priorObservation = evidence.keys.mapNotNull { id ->
            profile.skills[id]?.lastObservedAtEpochMillis
        }.maxOrNull()
        val weight = evidenceWeight(
            attempt.prompt.kind,
            attempt.assistance,
            priorObservation,
            nowEpochMillis,
        )

        val previousCount = profile.completedAttempts
        val updatedSkills = profile.skills.toMutableMap()
        evidence.forEach { (id, item) ->
            val previous = updatedSkills[id] ?: PracticeSkillState(
                id = id,
                family = item.family,
            )
            updatedSkills[id] = observe(previous, item.score, weight, nowEpochMillis)
        }
        profile = profile.copy(
            skills = updatedSkills,
            items = exposedItems(attempt.prompt.id, nowEpochMillis),
            completedAttempts = previousCount + 1,
            meanRawAccuracy = updatedMean(
                profile.meanRawAccuracy,
                previousCount,
                rawAlignment.accuracy,
            ),
            meanDecodedAccuracy = updatedMean(
                profile.meanDecodedAccuracy,
                previousCount,
                decodedAlignment.accuracy,
            ),
        )
        return PracticeResult(
            status = PracticeRecordStatus.RECORDED,
            rawAccuracy = rawAlignment.accuracy,
            decodedAccuracy = decodedAlignment.accuracy,
            evidenceWeight = weight,
            updatedSkillIds = evidence.keys,
        )
    }

    private fun exposedItems(promptId: String, nowEpochMillis: Long): Map<String, PracticeItemState> {
        val current = profile.items[promptId] ?: PracticeItemState(promptId)
        return profile.items + (
            promptId to current.copy(
                exposures = current.exposures + 1,
                lastPresentedAtEpochMillis = nowEpochMillis,
            )
        )
    }

    private fun staticEvidence(
        prompt: PracticePrompt,
        rawAccuracy: Double,
        decodedAccuracy: Double,
    ): Map<String, SkillEvidence> = prompt.skillIds.associateWith { id ->
        val family = family(id, prompt)
        SkillEvidence(
            family = family,
            score = if (family == PracticeSkillFamily.MOTOR) rawAccuracy else decodedAccuracy,
        )
    }

    private fun evidenceWeight(
        kind: PracticeKind,
        assistance: PracticeAssistance,
        previousObservationEpochMillis: Long?,
        nowEpochMillis: Long,
    ): Double {
        val kindWeight = when (kind) {
            PracticeKind.COPY -> 0.35
            PracticeKind.CLOZE, PracticeKind.CORRECTION -> 0.65
            PracticeKind.RECONSTRUCTION -> 0.85
            PracticeKind.FREE_PRODUCTION -> 1.0
            PracticeKind.MIXED_TRANSFER -> 0.95
        }
        val assistanceWeight = when (assistance) {
            PracticeAssistance.NONE -> 1.0
            PracticeAssistance.ADAPTIVE_KEYBOARD -> 0.75
            PracticeAssistance.SUGGESTION -> 0.45
            PracticeAssistance.CORRECTION -> 0.35
            PracticeAssistance.COPIED -> 0.25
        }
        val delayMultiplier = previousObservationEpochMillis?.let { previous ->
            val elapsedDays = max(0L, nowEpochMillis - previous).toDouble() / DAY_MILLIS.toDouble()
            when {
                elapsedDays >= 28.0 -> 1.5
                elapsedDays >= 7.0 -> 1.3
                elapsedDays >= 1.0 -> 1.15
                else -> 1.0
            }
        } ?: 1.0
        return min(1.5, kindWeight * assistanceWeight * delayMultiplier)
    }

    private fun family(id: String, prompt: PracticePrompt): PracticeSkillFamily = when {
        id.startsWith("motor:") -> PracticeSkillFamily.MOTOR
        id.startsWith("writing:") -> PracticeSkillFamily.WRITING
        prompt.track == PracticeTrack.MOTOR -> PracticeSkillFamily.MOTOR
        else -> PracticeSkillFamily.WRITING
    }

    private fun matches(track: PracticeTrack, prompt: PracticePrompt): Boolean =
        track == PracticeTrack.MIXED || prompt.track == track

    private fun observe(
        state: PracticeSkillState,
        score: Double,
        weight: Double,
        nowEpochMillis: Long,
    ): PracticeSkillState {
        val boundedScore = score.coerceIn(0.0, 1.0)
        val boundedWeight = max(0.0, weight)
        val successes = state.weightedSuccesses + boundedScore * boundedWeight
        val failures = state.weightedFailures + (1.0 - boundedScore) * boundedWeight
        val evidence = successes + failures
        val nextHalfLife = if (boundedScore >= 0.8) {
            state.halfLifeDays * (1.0 + 0.75 * boundedWeight * boundedScore)
        } else {
            state.halfLifeDays * max(0.5, 1.0 - 0.6 * boundedWeight * (1.0 - boundedScore))
        }
        return state.copy(
            observations = state.observations + 1,
            weightedSuccesses = successes,
            weightedFailures = failures,
            mastery = (1.0 + successes) / (2.0 + evidence),
            uncertainty = 2.0 / (2.0 + evidence),
            halfLifeDays = nextHalfLife.coerceIn(0.25, 365.0),
            lastObservedAtEpochMillis = nowEpochMillis,
            retentionSchedule = RETENTION_DAYS.map { day ->
                PracticeRetentionCheckpoint(
                    day = day,
                    dueAtEpochMillis = nowEpochMillis + day.toLong() * DAY_MILLIS,
                )
            },
        )
    }

    private fun motorEvidence(
        target: String,
        alignment: Alignment,
    ): Map<String, Double> {
        val characters = target.toList()
        val totals = mutableMapOf<String, Pair<Double, Double>>()
        characters.forEachIndexed { index, character ->
            val id = "motor:key:${skillToken(character)}"
            val current = totals[id] ?: (0.0 to 0.0)
            val success = if (alignment.targetObservations[index].matches) 1.0 else 0.0
            totals[id] = current.first + success to current.second + 1.0
        }
        for (index in 0 until max(0, characters.size - 1)) {
            val first = alignment.targetObservations[index]
            val second = alignment.targetObservations[index + 1]
            val consecutive = first.responseIndex?.plus(1) == second.responseIndex
            val success = if (first.matches && second.matches && consecutive) 1.0 else 0.0
            val id = "motor:transition:${skillToken(characters[index])}${skillToken(characters[index + 1])}"
            val current = totals[id] ?: (0.0 to 0.0)
            totals[id] = current.first + success to current.second + 1.0
        }
        return totals.mapValues { (_, value) -> value.first / value.second }
    }

    private fun align(target: String, response: String): Alignment {
        val targetCharacters = target.toList()
        val responseCharacters = response.toList()
        val targetCount = targetCharacters.size
        val responseCount = responseCharacters.size
        if (targetCount == 0) {
            return Alignment(
                accuracy = if (responseCount == 0) 1.0 else 0.0,
                targetObservations = emptyList(),
            )
        }

        val costs = Array(targetCount + 1) { IntArray(responseCount + 1) }
        for (index in 0..targetCount) costs[index][0] = index
        for (index in 0..responseCount) costs[0][index] = index
        for (targetIndex in 1..targetCount) {
            for (responseIndex in 1..responseCount) {
                val substitution = costs[targetIndex - 1][responseIndex - 1] +
                    if (targetCharacters[targetIndex - 1] == responseCharacters[responseIndex - 1]) 0 else 1
                val deletion = costs[targetIndex - 1][responseIndex] + 1
                val insertion = costs[targetIndex][responseIndex - 1] + 1
                costs[targetIndex][responseIndex] = min(substitution, min(deletion, insertion))
            }
        }

        val observations = MutableList(targetCount) { TargetObservation(false, null) }
        var targetIndex = targetCount
        var responseIndex = responseCount
        while (targetIndex > 0 || responseIndex > 0) {
            if (targetIndex > 0 && responseIndex > 0) {
                val matches = targetCharacters[targetIndex - 1] == responseCharacters[responseIndex - 1]
                val substitutionCost = if (matches) 0 else 1
                if (costs[targetIndex][responseIndex] ==
                    costs[targetIndex - 1][responseIndex - 1] + substitutionCost
                ) {
                    observations[targetIndex - 1] = TargetObservation(matches, responseIndex - 1)
                    targetIndex -= 1
                    responseIndex -= 1
                    continue
                }
            }
            if (targetIndex > 0 &&
                costs[targetIndex][responseIndex] == costs[targetIndex - 1][responseIndex] + 1
            ) {
                observations[targetIndex - 1] = TargetObservation(false, null)
                targetIndex -= 1
            } else {
                responseIndex -= 1
            }
        }

        val denominator = max(targetCount, responseCount)
        return Alignment(
            accuracy = (1.0 - costs[targetCount][responseCount].toDouble() / denominator).coerceIn(0.0, 1.0),
            targetObservations = observations,
        )
    }

    private fun updatedMean(current: Double, previousCount: Int, newValue: Double): Double =
        ((current * previousCount) + newValue) / (previousCount + 1)

    private fun skillToken(character: Char): String = when (character) {
        ' ' -> "space"
        '\n' -> "return"
        '\t' -> "tab"
        else -> character.lowercaseChar().toString()
    }

    private companion object {
        const val DAY_MILLIS = 86_400_000L
        val RETENTION_DAYS = listOf(1, 7, 28)

        val trainingItems = listOf(
            BankItem(
                prompt = PracticePrompt(
                    id = "motor-home",
                    kind = PracticeKind.COPY,
                    track = PracticeTrack.MOTOR,
                    instruction = "Type the word exactly as shown.",
                    stimulus = "home",
                    expectedText = "home",
                    motorTarget = "home",
                    skillIds = setOf("motor:key:e", "motor:transition:me"),
                ),
                frequency = 0.99,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "motor-the",
                    kind = PracticeKind.COPY,
                    track = PracticeTrack.MOTOR,
                    instruction = "Type the word exactly as shown.",
                    stimulus = "the",
                    expectedText = "the",
                    motorTarget = "the",
                    skillIds = setOf("motor:transition:th", "motor:key:e"),
                ),
                frequency = 0.97,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "motor-near",
                    kind = PracticeKind.COPY,
                    track = PracticeTrack.MOTOR,
                    instruction = "Keep a steady rhythm while copying.",
                    stimulus = "near the red door",
                    expectedText = "near the red door",
                    motorTarget = "near the red door",
                    skillIds = setOf("motor:key:e", "motor:confusion:e-r"),
                ),
                frequency = 0.90,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "motor-typing",
                    kind = PracticeKind.RECONSTRUCTION,
                    track = PracticeTrack.MOTOR,
                    instruction = "Type the phrase after it is hidden.",
                    stimulus = "typing feels natural",
                    expectedText = "typing feels natural",
                    motorTarget = "typing feels natural",
                    skillIds = setOf("motor:transition:ing", "motor:key:g"),
                ),
                frequency = 0.88,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "writing-article",
                    kind = PracticeKind.CLOZE,
                    track = PracticeTrack.WRITING,
                    instruction = "Fill the blank with the correct article.",
                    stimulus = "She ate __ apple after lunch.",
                    expectedText = "an",
                    skillIds = setOf("writing:articles:a-an"),
                ),
                frequency = 0.96,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "writing-agreement",
                    kind = PracticeKind.CORRECTION,
                    track = PracticeTrack.WRITING,
                    instruction = "Rewrite the sentence correctly.",
                    stimulus = "She go home every evening.",
                    expectedText = "She goes home every evening.",
                    skillIds = setOf("writing:agreement:third-person"),
                ),
                frequency = 0.94,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "writing-reconstruction",
                    kind = PracticeKind.RECONSTRUCTION,
                    track = PracticeTrack.WRITING,
                    instruction = "Reconstruct the sentence from memory.",
                    stimulus = "I finished the report before lunch.",
                    expectedText = "I finished the report before lunch.",
                    skillIds = setOf("writing:tense:simple-past"),
                ),
                frequency = 0.90,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "writing-free-production",
                    kind = PracticeKind.FREE_PRODUCTION,
                    track = PracticeTrack.WRITING,
                    instruction = "Write the sentence without using suggestions.",
                    stimulus = "Use the past tense of go with the destination home.",
                    expectedText = "I went home after work.",
                    skillIds = setOf("writing:tense:irregular-past"),
                ),
                frequency = 0.86,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "mixed-transfer-home",
                    kind = PracticeKind.MIXED_TRANSFER,
                    track = PracticeTrack.MIXED,
                    instruction = "Write the complete sentence from memory.",
                    stimulus = "We will meet at home tomorrow.",
                    expectedText = "We will meet at home tomorrow.",
                    motorTarget = "We will meet at home tomorrow.",
                    skillIds = setOf(
                        "motor:key:e",
                        "motor:transition:me",
                        "writing:time:future",
                    ),
                ),
                frequency = 0.84,
            ),
        )

        val holdoutItems = listOf(
            BankItem(
                prompt = PracticePrompt(
                    id = "holdout-motor-day-1-evening",
                    kind = PracticeKind.MIXED_TRANSFER,
                    track = PracticeTrack.MOTOR,
                    instruction = "Type the unseen phrase once.",
                    expectedText = "evening rain",
                    motorTarget = "evening rain",
                    skillIds = setOf("motor:key:e", "motor:transition:ing"),
                    isHoldout = true,
                ),
                frequency = 0.0,
                retentionDay = 1,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "holdout-motor-day-7-leaves",
                    kind = PracticeKind.MIXED_TRANSFER,
                    track = PracticeTrack.MOTOR,
                    instruction = "Type the unseen phrase once.",
                    expectedText = "green leaves",
                    motorTarget = "green leaves",
                    skillIds = setOf("motor:key:e", "motor:confusion:e-r"),
                    isHoldout = true,
                ),
                frequency = 0.0,
                retentionDay = 7,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "holdout-motor-day-28-remember",
                    kind = PracticeKind.MIXED_TRANSFER,
                    track = PracticeTrack.MOTOR,
                    instruction = "Type the unseen phrase once.",
                    expectedText = "remember the evening",
                    motorTarget = "remember the evening",
                    skillIds = setOf("motor:key:e", "motor:transition:ing"),
                    isHoldout = true,
                ),
                frequency = 0.0,
                retentionDay = 28,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "holdout-writing-day-1-article",
                    kind = PracticeKind.MIXED_TRANSFER,
                    track = PracticeTrack.WRITING,
                    instruction = "Complete the unseen sentence.",
                    stimulus = "He carried __ umbrella.",
                    expectedText = "an",
                    skillIds = setOf("writing:articles:a-an"),
                    isHoldout = true,
                ),
                frequency = 0.0,
                retentionDay = 1,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "holdout-writing-day-7-article",
                    kind = PracticeKind.MIXED_TRANSFER,
                    track = PracticeTrack.WRITING,
                    instruction = "Complete the unseen sentence.",
                    stimulus = "That was __ honest answer.",
                    expectedText = "an",
                    skillIds = setOf("writing:articles:a-an"),
                    isHoldout = true,
                ),
                frequency = 0.0,
                retentionDay = 7,
            ),
            BankItem(
                prompt = PracticePrompt(
                    id = "holdout-writing-day-28-article",
                    kind = PracticeKind.MIXED_TRANSFER,
                    track = PracticeTrack.WRITING,
                    instruction = "Complete the unseen sentence.",
                    stimulus = "It was __ unusual idea.",
                    expectedText = "an",
                    skillIds = setOf("writing:articles:a-an"),
                    isHoldout = true,
                ),
                frequency = 0.0,
                retentionDay = 28,
            ),
        )

        val holdoutIds = holdoutItems.mapTo(mutableSetOf()) { it.prompt.id }
    }
}
