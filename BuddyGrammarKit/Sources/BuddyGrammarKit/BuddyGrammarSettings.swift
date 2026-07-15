import Foundation

public struct BuddyGrammarSettings: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case openRouterModelID
        case usesAutomaticModelUpdates
        case correctionInstruction
        case autoCorrectDictation
        case automaticallyCorrectWords
        case correctionUndoDuration
        case hasAcceptedCloudProcessing
        case hasCompletedOnboarding
        case enablesQuickDictation
    }

    public var openRouterModelID: String
    public var usesAutomaticModelUpdates: Bool
    public var correctionInstruction: String
    public var autoCorrectDictation: Bool
    public var automaticallyCorrectWords: Bool
    public var correctionUndoDuration: TimeInterval
    public var hasAcceptedCloudProcessing: Bool
    public var hasCompletedOnboarding: Bool
    public var enablesQuickDictation: Bool

    public init(
        openRouterModelID: String = BuddyGrammarConfiguration.defaultOpenRouterModelID,
        usesAutomaticModelUpdates: Bool? = nil,
        correctionInstruction: String = BuddyGrammarConfiguration.standardCorrectionInstruction,
        autoCorrectDictation: Bool = true,
        automaticallyCorrectWords: Bool = true,
        correctionUndoDuration: TimeInterval = 3,
        hasAcceptedCloudProcessing: Bool = false,
        hasCompletedOnboarding: Bool = false,
        enablesQuickDictation: Bool = false
    ) {
        let usesAutomaticModelUpdates = usesAutomaticModelUpdates
            ?? BuddyGrammarConfiguration.managedOpenRouterModelIDs.contains(openRouterModelID)
        self.openRouterModelID = usesAutomaticModelUpdates
            ? BuddyGrammarConfiguration.defaultOpenRouterModelID
            : openRouterModelID
        self.usesAutomaticModelUpdates = usesAutomaticModelUpdates
        self.correctionInstruction = correctionInstruction
        self.autoCorrectDictation = autoCorrectDictation
        self.automaticallyCorrectWords = automaticallyCorrectWords
        self.correctionUndoDuration = Self.clampedUndoDuration(correctionUndoDuration)
        self.hasAcceptedCloudProcessing = hasAcceptedCloudProcessing
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.enablesQuickDictation = enablesQuickDictation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedModelID = try container.decodeIfPresent(
            String.self,
            forKey: .openRouterModelID
        ) ?? BuddyGrammarConfiguration.defaultOpenRouterModelID
        usesAutomaticModelUpdates = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesAutomaticModelUpdates
        ) ?? BuddyGrammarConfiguration.managedOpenRouterModelIDs.contains(decodedModelID)
        openRouterModelID = usesAutomaticModelUpdates
            ? BuddyGrammarConfiguration.defaultOpenRouterModelID
            : decodedModelID

        let decodedInstruction = try container.decodeIfPresent(
            String.self,
            forKey: .correctionInstruction
        ) ?? BuddyGrammarConfiguration.standardCorrectionInstruction
        correctionInstruction = decodedInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            == BuddyGrammarConfiguration.legacyStandardCorrectionInstruction
            ? BuddyGrammarConfiguration.standardCorrectionInstruction
            : decodedInstruction

        autoCorrectDictation = try container.decodeIfPresent(
            Bool.self,
            forKey: .autoCorrectDictation
        ) ?? true
        automaticallyCorrectWords = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticallyCorrectWords
        ) ?? true
        correctionUndoDuration = Self.clampedUndoDuration(
            try container.decodeIfPresent(
                TimeInterval.self,
                forKey: .correctionUndoDuration
            ) ?? 3
        )
        hasAcceptedCloudProcessing = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAcceptedCloudProcessing
        ) ?? false
        hasCompletedOnboarding = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedOnboarding
        ) ?? false
        enablesQuickDictation = try container.decodeIfPresent(
            Bool.self,
            forKey: .enablesQuickDictation
        ) ?? false
    }

    public static func clampedUndoDuration(_ duration: TimeInterval) -> TimeInterval {
        min(10, max(1, duration))
    }

    public var activeOpenRouterModelID: String {
        usesAutomaticModelUpdates
            ? BuddyGrammarConfiguration.defaultOpenRouterModelID
            : openRouterModelID
    }

    public static let `default` = BuddyGrammarSettings()
}

public struct PendingTranscript: Codable, Equatable, Sendable {
    public let text: String
    public let languageCode: String?
    public let createdAt: Date

    public init(
        text: String,
        languageCode: String? = nil,
        createdAt: Date = .now
    ) {
        self.text = text
        self.languageCode = languageCode
        self.createdAt = createdAt
    }
}

/// The latest completed dictation kept locally by the app. Unlike
/// `PendingTranscript`, this is not consumed by the keyboard or expired after
/// the keyboard handoff window.
public struct SavedDictation: Codable, Equatable, Sendable {
    public let rawTranscript: String
    public let text: String
    public let languageCode: String?
    public let createdAt: Date

    public init(
        rawTranscript: String,
        text: String,
        languageCode: String? = nil,
        createdAt: Date = .now
    ) {
        self.rawTranscript = rawTranscript
        self.text = text
        self.languageCode = languageCode
        self.createdAt = createdAt
    }
}
