import Foundation

public enum PracticeKind: String, CaseIterable, Codable, Equatable, Sendable {
    case copy
    case cloze
    case correction
    case reconstruction
    case freeProduction
    case mixedTransfer
}

public enum PracticeTrack: String, CaseIterable, Codable, Equatable, Sendable {
    case motor
    case writing
    case mixed
}

public struct PracticeRequest: Codable, Equatable, Sendable {
    public var track: PracticeTrack
    public var preferredKinds: [PracticeKind]
    public var goalSkillIDs: [String]
    public var retentionDay: Int?

    public init(
        track: PracticeTrack = .mixed,
        preferredKinds: [PracticeKind] = [],
        goalSkillIDs: [String] = [],
        retentionDay: Int? = nil
    ) {
        self.track = track
        self.preferredKinds = preferredKinds
        self.goalSkillIDs = goalSkillIDs
        self.retentionDay = retentionDay
    }
}

public struct PracticePrompt: Codable, Equatable, Sendable {
    public let id: String
    public let kind: PracticeKind
    public let track: PracticeTrack
    public let instruction: String
    public let stimulus: String?
    public let expectedText: String
    public let motorTarget: String?
    public let skillIDs: [String]
    public let isHoldout: Bool

    public init(
        id: String,
        kind: PracticeKind,
        track: PracticeTrack,
        instruction: String,
        stimulus: String? = nil,
        expectedText: String,
        motorTarget: String? = nil,
        skillIDs: [String],
        isHoldout: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.track = track
        self.instruction = instruction
        self.stimulus = stimulus
        self.expectedText = expectedText
        self.motorTarget = motorTarget
        self.skillIDs = skillIDs
        self.isHoldout = isHoldout
    }
}

public enum PracticeAssistance: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case adaptiveKeyboard
    case suggestion
    case correction
    case copied
}

public struct PracticeAttempt: Codable, Equatable, Sendable {
    public let prompt: PracticePrompt
    public let rawText: String
    public let decodedText: String
    public let assistance: PracticeAssistance
    public let abandoned: Bool

    public init(
        prompt: PracticePrompt,
        rawText: String,
        decodedText: String? = nil,
        assistance: PracticeAssistance = .none,
        abandoned: Bool = false
    ) {
        self.prompt = prompt
        self.rawText = rawText
        self.decodedText = decodedText ?? rawText
        self.assistance = assistance
        self.abandoned = abandoned
    }
}

public enum PracticeRecordStatus: String, Codable, Equatable, Sendable {
    case recorded
    case abandoned
    case holdout
}

public struct PracticeResult: Codable, Equatable, Sendable {
    public let status: PracticeRecordStatus
    public let rawAccuracy: Double
    public let decodedAccuracy: Double
    public let evidenceWeight: Double
    public let updatedSkillIDs: [String]

    public init(
        status: PracticeRecordStatus,
        rawAccuracy: Double,
        decodedAccuracy: Double,
        evidenceWeight: Double,
        updatedSkillIDs: [String]
    ) {
        self.status = status
        self.rawAccuracy = rawAccuracy
        self.decodedAccuracy = decodedAccuracy
        self.evidenceWeight = evidenceWeight
        self.updatedSkillIDs = updatedSkillIDs
    }
}

public enum PracticeSkillFamily: String, Codable, Equatable, Sendable {
    case motor
    case writing
}

public struct PracticeRetentionCheckpoint: Codable, Equatable, Sendable {
    public let day: Int
    public let dueAt: Date

    public init(day: Int, dueAt: Date) {
        self.day = day
        self.dueAt = dueAt
    }
}

public struct PracticeSkillState: Codable, Equatable, Sendable {
    public let id: String
    public let family: PracticeSkillFamily
    public fileprivate(set) var observations: Int
    public fileprivate(set) var weightedSuccesses: Double
    public fileprivate(set) var weightedFailures: Double
    public fileprivate(set) var mastery: Double
    public fileprivate(set) var uncertainty: Double
    public fileprivate(set) var halfLifeDays: Double
    public fileprivate(set) var lastObservedAt: Date?
    public fileprivate(set) var retentionSchedule: [PracticeRetentionCheckpoint]

    public init(
        id: String,
        family: PracticeSkillFamily,
        observations: Int = 0,
        weightedSuccesses: Double = 0,
        weightedFailures: Double = 0,
        mastery: Double = 0.5,
        uncertainty: Double = 1,
        halfLifeDays: Double = 1,
        lastObservedAt: Date? = nil,
        retentionSchedule: [PracticeRetentionCheckpoint] = []
    ) {
        self.id = id
        self.family = family
        self.observations = max(0, observations)
        self.weightedSuccesses = max(0, weightedSuccesses)
        self.weightedFailures = max(0, weightedFailures)
        self.mastery = Self.clamp(mastery)
        self.uncertainty = Self.clamp(uncertainty)
        self.halfLifeDays = max(0.25, halfLifeDays)
        self.lastObservedAt = lastObservedAt
        self.retentionSchedule = retentionSchedule.sorted { $0.day < $1.day }
    }

    fileprivate mutating func observe(
        score: Double,
        weight: Double,
        now: Date
    ) {
        let score = Self.clamp(score)
        let weight = max(0, weight)
        weightedSuccesses += score * weight
        weightedFailures += (1 - score) * weight
        observations += 1

        let evidence = weightedSuccesses + weightedFailures
        mastery = (1 + weightedSuccesses) / (2 + evidence)
        uncertainty = 2 / (2 + evidence)

        if score >= 0.8 {
            halfLifeDays *= 1 + (0.75 * weight * score)
        } else {
            halfLifeDays *= max(0.5, 1 - (0.6 * weight * (1 - score)))
        }
        halfLifeDays = min(365, max(0.25, halfLifeDays))
        lastObservedAt = now
        retentionSchedule = [1, 7, 28].map { day in
            PracticeRetentionCheckpoint(
                day: day,
                dueAt: now.addingTimeInterval(Double(day) * 86_400)
            )
        }
    }

    fileprivate func priority(
        at now: Date,
        frequency: Double,
        goalImpact: Double
    ) -> Double {
        guard let lastObservedAt else {
            return 0.4 * uncertainty * frequency * goalImpact
        }
        let elapsedDays = max(0, now.timeIntervalSince(lastObservedAt) / 86_400)
        let predictedRecall = pow(2, -elapsedDays / max(0.25, halfLifeDays))
        let forgettingRisk = max(1 - predictedRecall, 1 - mastery)
        return forgettingRisk * uncertainty * frequency * goalImpact
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public struct PracticeItemState: Codable, Equatable, Sendable {
    public let id: String
    public fileprivate(set) var exposures: Int
    public fileprivate(set) var lastPresentedAt: Date?

    public init(id: String, exposures: Int = 0, lastPresentedAt: Date? = nil) {
        self.id = id
        self.exposures = max(0, exposures)
        self.lastPresentedAt = lastPresentedAt
    }
}

public struct PracticeProfile: Codable, Equatable, Sendable {
    public fileprivate(set) var skills: [String: PracticeSkillState]
    public fileprivate(set) var items: [String: PracticeItemState]
    public fileprivate(set) var completedAttempts: Int
    public fileprivate(set) var abandonedAttempts: Int
    public fileprivate(set) var meanRawAccuracy: Double
    public fileprivate(set) var meanDecodedAccuracy: Double

    public init(
        skills: [String: PracticeSkillState] = [:],
        items: [String: PracticeItemState] = [:],
        completedAttempts: Int = 0,
        abandonedAttempts: Int = 0,
        meanRawAccuracy: Double = 0,
        meanDecodedAccuracy: Double = 0
    ) {
        self.skills = skills
        self.items = items
        self.completedAttempts = max(0, completedAttempts)
        self.abandonedAttempts = max(0, abandonedAttempts)
        self.meanRawAccuracy = min(1, max(0, meanRawAccuracy))
        self.meanDecodedAccuracy = min(1, max(0, meanDecodedAccuracy))
    }
}

public struct PracticeCoach: Sendable {
    private struct BankItem: Sendable {
        let prompt: PracticePrompt
        let frequency: Double
        let retentionDay: Int?

        init(
            prompt: PracticePrompt,
            frequency: Double,
            retentionDay: Int? = nil
        ) {
            self.prompt = prompt
            self.frequency = frequency
            self.retentionDay = retentionDay
        }
    }

    private struct TargetObservation {
        let matches: Bool
        let responseIndex: Int?
    }

    private struct Alignment {
        let accuracy: Double
        let targetObservations: [TargetObservation]
    }

    private struct SkillEvidence {
        let family: PracticeSkillFamily
        let score: Double
    }

    private var profile: PracticeProfile

    public init(profile: PracticeProfile = PracticeProfile()) {
        self.profile = profile
    }

    public var snapshot: PracticeProfile {
        profile
    }

    public func nextPrompt(
        request: PracticeRequest,
        now: Date
    ) -> PracticePrompt {
        if let day = request.retentionDay, [1, 7, 28].contains(day) {
            let holdouts = Self.holdoutItems.filter { item in
                Self.matches(track: request.track, prompt: item.prompt)
                    && item.retentionDay == day
            }
            if let holdout = holdouts.sorted(by: { $0.prompt.id < $1.prompt.id }).first {
                return holdout.prompt
            }
        }

        let trackCandidates = Self.trainingItems.filter { item in
            Self.matches(track: request.track, prompt: item.prompt)
        }
        let preferredCandidates = trackCandidates.filter { item in
            request.preferredKinds.isEmpty
                || request.preferredKinds.contains(item.prompt.kind)
        }
        let candidates = preferredCandidates.isEmpty ? trackCandidates : preferredCandidates
        return candidates.sorted { lhs, rhs in
            let lhsScore = selectionScore(for: lhs, request: request, now: now)
            let rhsScore = selectionScore(for: rhs, request: request, now: now)
            if abs(lhsScore - rhsScore) > 0.000_001 {
                return lhsScore > rhsScore
            }
            return lhs.prompt.id < rhs.prompt.id
        }.first?.prompt ?? Self.trainingItems[0].prompt
    }

    @discardableResult
    public mutating func record(
        attempt: PracticeAttempt,
        now: Date
    ) -> PracticeResult {
        let rawAlignment = Self.align(
            target: attempt.prompt.expectedText,
            response: attempt.rawText
        )
        let decodedAlignment = Self.align(
            target: attempt.prompt.expectedText,
            response: attempt.decodedText
        )

        if attempt.prompt.isHoldout || Self.holdoutIDs.contains(attempt.prompt.id) {
            return PracticeResult(
                status: .holdout,
                rawAccuracy: rawAlignment.accuracy,
                decodedAccuracy: decodedAlignment.accuracy,
                evidenceWeight: 0,
                updatedSkillIDs: []
            )
        }

        if attempt.abandoned {
            profile.abandonedAttempts += 1
            recordExposure(for: attempt.prompt.id, now: now)
            return PracticeResult(
                status: .abandoned,
                rawAccuracy: rawAlignment.accuracy,
                decodedAccuracy: decodedAlignment.accuracy,
                evidenceWeight: 0,
                updatedSkillIDs: []
            )
        }

        let previousCount = profile.completedAttempts
        profile.completedAttempts += 1
        profile.meanRawAccuracy = Self.updatedMean(
            current: profile.meanRawAccuracy,
            previousCount: previousCount,
            newValue: rawAlignment.accuracy
        )
        profile.meanDecodedAccuracy = Self.updatedMean(
            current: profile.meanDecodedAccuracy,
            previousCount: previousCount,
            newValue: decodedAlignment.accuracy
        )
        recordExposure(for: attempt.prompt.id, now: now)

        var evidence = staticEvidence(
            for: attempt.prompt,
            rawAccuracy: rawAlignment.accuracy,
            decodedAccuracy: decodedAlignment.accuracy
        )
        if let motorTarget = attempt.prompt.motorTarget {
            let motorAlignment = Self.align(target: motorTarget, response: attempt.rawText)
            for (id, value) in Self.motorEvidence(
                target: motorTarget,
                alignment: motorAlignment
            ) {
                evidence[id] = value
            }
        }

        let priorObservation = evidence.keys
            .compactMap { profile.skills[$0]?.lastObservedAt }
            .max()
        let weight = Self.evidenceWeight(
            kind: attempt.prompt.kind,
            assistance: attempt.assistance,
            previousObservation: priorObservation,
            now: now
        )

        for id in evidence.keys.sorted() {
            guard let item = evidence[id] else { continue }
            var state = profile.skills[id] ?? PracticeSkillState(
                id: id,
                family: item.family
            )
            state.observe(score: item.score, weight: weight, now: now)
            profile.skills[id] = state
        }

        return PracticeResult(
            status: .recorded,
            rawAccuracy: rawAlignment.accuracy,
            decodedAccuracy: decodedAlignment.accuracy,
            evidenceWeight: weight,
            updatedSkillIDs: evidence.keys.sorted()
        )
    }

    private func selectionScore(
        for item: BankItem,
        request: PracticeRequest,
        now: Date
    ) -> Double {
        let priorities = item.prompt.skillIDs.map { id -> Double in
            let family = Self.family(for: id, prompt: item.prompt)
            let state = profile.skills[id] ?? PracticeSkillState(id: id, family: family)
            let goalImpact = request.goalSkillIDs.contains(id) ? 1.8 : 1
            return state.priority(
                at: now,
                frequency: item.frequency,
                goalImpact: goalImpact
            )
        }
        let learningPriority = priorities.isEmpty
            ? 0.4 * item.frequency
            : priorities.reduce(0, +) / Double(priorities.count)
        let exposure = profile.items[item.prompt.id]?.exposures ?? 0
        let coverage = 1 / Double(1 + exposure)
        return learningPriority * coverage
    }

    private mutating func recordExposure(for id: String, now: Date) {
        var state = profile.items[id] ?? PracticeItemState(id: id)
        state.exposures += 1
        state.lastPresentedAt = now
        profile.items[id] = state
    }

    private func staticEvidence(
        for prompt: PracticePrompt,
        rawAccuracy: Double,
        decodedAccuracy: Double
    ) -> [String: SkillEvidence] {
        var evidence: [String: SkillEvidence] = [:]
        for id in prompt.skillIDs {
            let family = Self.family(for: id, prompt: prompt)
            let score = family == .motor ? rawAccuracy : decodedAccuracy
            evidence[id] = SkillEvidence(family: family, score: score)
        }
        return evidence
    }

    private static func motorEvidence(
        target: String,
        alignment: Alignment
    ) -> [String: SkillEvidence] {
        let characters = Array(target)
        var scores: [String: (successes: Double, trials: Double)] = [:]

        for (index, character) in characters.enumerated() {
            let id = "motor:key:\(skillToken(for: character))"
            let success = alignment.targetObservations[index].matches ? 1.0 : 0.0
            scores[id, default: (0, 0)].successes += success
            scores[id, default: (0, 0)].trials += 1
        }

        guard characters.count > 1 else {
            return scores.mapValues { value in
                SkillEvidence(family: .motor, score: value.successes / value.trials)
            }
        }
        for index in 0..<(characters.count - 1) {
            let first = alignment.targetObservations[index]
            let second = alignment.targetObservations[index + 1]
            let consecutive = first.responseIndex.map { firstIndex in
                second.responseIndex == firstIndex + 1
            } ?? false
            let success = first.matches && second.matches && consecutive ? 1.0 : 0.0
            let transition = skillToken(for: characters[index])
                + skillToken(for: characters[index + 1])
            let id = "motor:transition:\(transition)"
            scores[id, default: (0, 0)].successes += success
            scores[id, default: (0, 0)].trials += 1
        }
        return scores.mapValues { value in
            SkillEvidence(family: .motor, score: value.successes / value.trials)
        }
    }

    private static func evidenceWeight(
        kind: PracticeKind,
        assistance: PracticeAssistance,
        previousObservation: Date?,
        now: Date
    ) -> Double {
        let kindWeight: Double = switch kind {
        case .copy: 0.35
        case .cloze, .correction: 0.65
        case .reconstruction: 0.85
        case .freeProduction: 1
        case .mixedTransfer: 0.95
        }
        let assistanceWeight: Double = switch assistance {
        case .none: 1
        case .adaptiveKeyboard: 0.75
        case .suggestion: 0.45
        case .correction: 0.35
        case .copied: 0.25
        }
        let delayMultiplier: Double
        if let previousObservation {
            let elapsedDays = max(0, now.timeIntervalSince(previousObservation) / 86_400)
            if elapsedDays >= 28 {
                delayMultiplier = 1.5
            } else if elapsedDays >= 7 {
                delayMultiplier = 1.3
            } else if elapsedDays >= 1 {
                delayMultiplier = 1.15
            } else {
                delayMultiplier = 1
            }
        } else {
            delayMultiplier = 1
        }
        return min(1.5, kindWeight * assistanceWeight * delayMultiplier)
    }

    private static func family(
        for id: String,
        prompt: PracticePrompt
    ) -> PracticeSkillFamily {
        if id.hasPrefix("motor:") { return .motor }
        if id.hasPrefix("writing:") { return .writing }
        return prompt.track == .motor ? .motor : .writing
    }

    private static func matches(track: PracticeTrack, prompt: PracticePrompt) -> Bool {
        track == .mixed || prompt.track == track
    }

    private static func skillToken(for character: Character) -> String {
        switch character {
        case " ": return "space"
        case "\n": return "return"
        case "\t": return "tab"
        default: return String(character).lowercased()
        }
    }

    private static func updatedMean(
        current: Double,
        previousCount: Int,
        newValue: Double
    ) -> Double {
        ((current * Double(previousCount)) + newValue) / Double(previousCount + 1)
    }

    private static func align(target: String, response: String) -> Alignment {
        let target = Array(target)
        let response = Array(response)
        let targetCount = target.count
        let responseCount = response.count
        guard targetCount > 0 else {
            return Alignment(
                accuracy: responseCount == 0 ? 1 : 0,
                targetObservations: []
            )
        }

        var costs = Array(
            repeating: Array(repeating: 0, count: responseCount + 1),
            count: targetCount + 1
        )
        for index in 0...targetCount { costs[index][0] = index }
        for index in 0...responseCount { costs[0][index] = index }
        if targetCount > 0, responseCount > 0 {
            for targetIndex in 1...targetCount {
                for responseIndex in 1...responseCount {
                    let substitution = costs[targetIndex - 1][responseIndex - 1]
                        + (target[targetIndex - 1] == response[responseIndex - 1] ? 0 : 1)
                    let deletion = costs[targetIndex - 1][responseIndex] + 1
                    let insertion = costs[targetIndex][responseIndex - 1] + 1
                    costs[targetIndex][responseIndex] = min(
                        substitution,
                        min(deletion, insertion)
                    )
                }
            }
        }

        var observations = Array(
            repeating: TargetObservation(matches: false, responseIndex: nil),
            count: targetCount
        )
        var targetIndex = targetCount
        var responseIndex = responseCount
        while targetIndex > 0 || responseIndex > 0 {
            if targetIndex > 0, responseIndex > 0 {
                let charactersMatch = target[targetIndex - 1] == response[responseIndex - 1]
                let substitutionCost = charactersMatch ? 0 : 1
                if costs[targetIndex][responseIndex]
                    == costs[targetIndex - 1][responseIndex - 1] + substitutionCost {
                    observations[targetIndex - 1] = TargetObservation(
                        matches: charactersMatch,
                        responseIndex: responseIndex - 1
                    )
                    targetIndex -= 1
                    responseIndex -= 1
                    continue
                }
            }
            if targetIndex > 0,
               costs[targetIndex][responseIndex] == costs[targetIndex - 1][responseIndex] + 1 {
                observations[targetIndex - 1] = TargetObservation(
                    matches: false,
                    responseIndex: nil
                )
                targetIndex -= 1
            } else {
                responseIndex -= 1
            }
        }

        let denominator = max(targetCount, responseCount)
        let accuracy = denominator == 0
            ? 1
            : 1 - (Double(costs[targetCount][responseCount]) / Double(denominator))
        return Alignment(
            accuracy: min(1, max(0, accuracy)),
            targetObservations: observations
        )
    }

    private static let trainingItems: [BankItem] = [
        BankItem(
            prompt: PracticePrompt(
                id: "motor-home",
                kind: .copy,
                track: .motor,
                instruction: "Type the word exactly as shown.",
                stimulus: "home",
                expectedText: "home",
                motorTarget: "home",
                skillIDs: ["motor:key:e", "motor:transition:me"]
            ),
            frequency: 0.99
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "motor-the",
                kind: .copy,
                track: .motor,
                instruction: "Type the word exactly as shown.",
                stimulus: "the",
                expectedText: "the",
                motorTarget: "the",
                skillIDs: ["motor:transition:th", "motor:key:e"]
            ),
            frequency: 0.97
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "motor-near",
                kind: .copy,
                track: .motor,
                instruction: "Keep a steady rhythm while copying.",
                stimulus: "near the red door",
                expectedText: "near the red door",
                motorTarget: "near the red door",
                skillIDs: ["motor:key:e", "motor:confusion:e-r"]
            ),
            frequency: 0.9
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "motor-typing",
                kind: .reconstruction,
                track: .motor,
                instruction: "Type the phrase after it is hidden.",
                stimulus: "typing feels natural",
                expectedText: "typing feels natural",
                motorTarget: "typing feels natural",
                skillIDs: ["motor:transition:ing", "motor:key:g"]
            ),
            frequency: 0.88
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "writing-article",
                kind: .cloze,
                track: .writing,
                instruction: "Fill the blank with the correct article.",
                stimulus: "She ate __ apple after lunch.",
                expectedText: "an",
                skillIDs: ["writing:articles:a-an"]
            ),
            frequency: 0.96
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "writing-agreement",
                kind: .correction,
                track: .writing,
                instruction: "Rewrite the sentence correctly.",
                stimulus: "She go home every evening.",
                expectedText: "She goes home every evening.",
                skillIDs: ["writing:agreement:third-person"]
            ),
            frequency: 0.94
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "writing-reconstruction",
                kind: .reconstruction,
                track: .writing,
                instruction: "Reconstruct the sentence from memory.",
                stimulus: "I finished the report before lunch.",
                expectedText: "I finished the report before lunch.",
                skillIDs: ["writing:tense:simple-past"]
            ),
            frequency: 0.9
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "writing-free-production",
                kind: .freeProduction,
                track: .writing,
                instruction: "Write the sentence without using suggestions.",
                stimulus: "Use the past tense of go with the destination home.",
                expectedText: "I went home after work.",
                skillIDs: ["writing:tense:irregular-past"]
            ),
            frequency: 0.86
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "mixed-transfer-home",
                kind: .mixedTransfer,
                track: .mixed,
                instruction: "Write the complete sentence from memory.",
                stimulus: "We will meet at home tomorrow.",
                expectedText: "We will meet at home tomorrow.",
                motorTarget: "We will meet at home tomorrow.",
                skillIDs: [
                    "motor:key:e",
                    "motor:transition:me",
                    "writing:time:future",
                ]
            ),
            frequency: 0.84
        ),
    ]

    private static let holdoutItems: [BankItem] = [
        BankItem(
            prompt: PracticePrompt(
                id: "holdout-motor-day-1-evening",
                kind: .mixedTransfer,
                track: .motor,
                instruction: "Type the unseen phrase once.",
                expectedText: "evening rain",
                motorTarget: "evening rain",
                skillIDs: ["motor:key:e", "motor:transition:ing"],
                isHoldout: true
            ),
            frequency: 0,
            retentionDay: 1
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "holdout-motor-day-7-leaves",
                kind: .mixedTransfer,
                track: .motor,
                instruction: "Type the unseen phrase once.",
                expectedText: "green leaves",
                motorTarget: "green leaves",
                skillIDs: ["motor:key:e", "motor:confusion:e-r"],
                isHoldout: true
            ),
            frequency: 0,
            retentionDay: 7
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "holdout-motor-day-28-remember",
                kind: .mixedTransfer,
                track: .motor,
                instruction: "Type the unseen phrase once.",
                expectedText: "remember the evening",
                motorTarget: "remember the evening",
                skillIDs: ["motor:key:e", "motor:transition:ing"],
                isHoldout: true
            ),
            frequency: 0,
            retentionDay: 28
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "holdout-writing-day-1-article",
                kind: .mixedTransfer,
                track: .writing,
                instruction: "Complete the unseen sentence.",
                stimulus: "He carried __ umbrella.",
                expectedText: "an",
                skillIDs: ["writing:articles:a-an"],
                isHoldout: true
            ),
            frequency: 0,
            retentionDay: 1
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "holdout-writing-day-7-article",
                kind: .mixedTransfer,
                track: .writing,
                instruction: "Complete the unseen sentence.",
                stimulus: "That was __ honest answer.",
                expectedText: "an",
                skillIDs: ["writing:articles:a-an"],
                isHoldout: true
            ),
            frequency: 0,
            retentionDay: 7
        ),
        BankItem(
            prompt: PracticePrompt(
                id: "holdout-writing-day-28-article",
                kind: .mixedTransfer,
                track: .writing,
                instruction: "Complete the unseen sentence.",
                stimulus: "It was __ unusual idea.",
                expectedText: "an",
                skillIDs: ["writing:articles:a-an"],
                isHoldout: true
            ),
            frequency: 0,
            retentionDay: 28
        ),
    ]

    private static let holdoutIDs = Set(holdoutItems.map(\.prompt.id))
}
