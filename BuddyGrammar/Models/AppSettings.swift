import Foundation

enum OutputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case replaceSelection
    case copyToClipboard

    var id: Self { self }

    var title: String {
        switch self {
        case .replaceSelection:
            "Replace Selected Text"
        case .copyToClipboard:
            "Copy To Clipboard"
        }
    }
}

enum RewriteProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openRouter
    case local

    var id: Self { self }

    var title: String {
        switch self {
        case .openRouter:
            "OpenRouter"
        case .local:
            "Local Models"
        }
    }
}

enum OpenRouterModel {
    static let defaultID = "openai/gpt-5.4-nano"
}

enum LocalModelID: String, Codable, CaseIterable, Identifiable, Sendable {
    case qwen3_4b_instruct_2507_4bit
    case gemma4_e4b_it_mxfp8

    var id: Self { self }

    var title: String {
        switch self {
        case .qwen3_4b_instruct_2507_4bit:
            "Qwen 4B Fast"
        case .gemma4_e4b_it_mxfp8:
            "Gemma 4 E4B"
        }
    }

    var repositoryID: String {
        switch self {
        case .qwen3_4b_instruct_2507_4bit:
            "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        case .gemma4_e4b_it_mxfp8:
            "mlx-community/gemma-4-e4b-it-mxfp8"
        }
    }

    var summary: String {
        switch self {
        case .qwen3_4b_instruct_2507_4bit:
            "Smallest local model. Best default for instant grammar fixes."
        case .gemma4_e4b_it_mxfp8:
            "Heavier multilingual fallback. Better kept for benchmarking."
        }
    }

    var badge: String {
        switch self {
        case .qwen3_4b_instruct_2507_4bit:
            "~2.1 GB"
        case .gemma4_e4b_it_mxfp8:
            "~8.1 GB"
        }
    }

    var isAdvanced: Bool {
        switch self {
        case .qwen3_4b_instruct_2507_4bit:
            false
        case .gemma4_e4b_it_mxfp8:
            true
        }
    }
}

enum RewriteProvider: Hashable, Sendable {
    case openRouter(modelID: String)
    case local(modelID: LocalModelID)

    var kind: RewriteProviderKind {
        switch self {
        case .openRouter:
            .openRouter
        case .local:
            .local
        }
    }

    var modelLabel: String {
        switch self {
        case .openRouter(let modelID):
            modelID
        case .local(let modelID):
            modelID.title
        }
    }

    var localModelID: LocalModelID? {
        guard case .local(let modelID) = self else { return nil }
        return modelID
    }

    var openRouterModelID: String? {
        guard case .openRouter(let modelID) = self else { return nil }
        return modelID
    }
}

extension RewriteProvider: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case modelID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(RewriteProviderKind.self, forKey: .kind)
        switch kind {
        case .openRouter:
            let modelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? OpenRouterModel.defaultID
            self = .openRouter(modelID: modelID)
        case .local:
            let modelID = try container.decodeIfPresent(LocalModelID.self, forKey: .modelID)
                ?? .qwen3_4b_instruct_2507_4bit
            self = .local(modelID: modelID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .openRouter(let modelID):
            try container.encode(modelID, forKey: .modelID)
        case .local(let modelID):
            try container.encode(modelID, forKey: .modelID)
        }
    }
}

enum LocalModelState: String, Codable, Hashable, Sendable {
    case notDownloaded
    case downloading
    case ready
    case loading
    case loaded
    case failed

    var title: String {
        switch self {
        case .notDownloaded:
            "Not downloaded"
        case .downloading:
            "Downloading"
        case .ready:
            "Ready"
        case .loading:
            "Loading"
        case .loaded:
            "Loaded"
        case .failed:
            "Failed"
        }
    }
}

struct LocalModelStatus: Hashable, Sendable {
    var state: LocalModelState
    var progress: Double?
    var errorMessage: String?

    static let notDownloaded = LocalModelStatus(state: .notDownloaded, progress: nil, errorMessage: nil)
}

struct AppSettings: Codable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case outputMode
        case rewriteProvider
        case selectedLocalModel
        case preloadLocalModelOnLaunch
        case launchAtLogin
        case hasCompletedOnboarding
    }

    var outputMode: OutputMode
    var rewriteProvider: RewriteProvider
    var selectedLocalModel: LocalModelID
    var preloadLocalModelOnLaunch: Bool
    var launchAtLogin: Bool
    var hasCompletedOnboarding: Bool

    init(
        outputMode: OutputMode,
        rewriteProvider: RewriteProvider,
        selectedLocalModel: LocalModelID,
        preloadLocalModelOnLaunch: Bool,
        launchAtLogin: Bool,
        hasCompletedOnboarding: Bool
    ) {
        self.outputMode = outputMode
        self.rewriteProvider = rewriteProvider
        self.selectedLocalModel = selectedLocalModel
        self.preloadLocalModelOnLaunch = preloadLocalModelOnLaunch
        self.launchAtLogin = launchAtLogin
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputMode = try container.decodeIfPresent(OutputMode.self, forKey: .outputMode) ?? .replaceSelection
        let decodedProvider = try container.decodeIfPresent(RewriteProvider.self, forKey: .rewriteProvider)
            ?? .openRouter(modelID: OpenRouterModel.defaultID)
        rewriteProvider = decodedProvider
        selectedLocalModel = try container.decodeIfPresent(LocalModelID.self, forKey: .selectedLocalModel)
            ?? decodedProvider.localModelID
            ?? .qwen3_4b_instruct_2507_4bit
        preloadLocalModelOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .preloadLocalModelOnLaunch) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }

    static let `default` = AppSettings(
        outputMode: .replaceSelection,
        rewriteProvider: .openRouter(modelID: OpenRouterModel.defaultID),
        selectedLocalModel: .qwen3_4b_instruct_2507_4bit,
        preloadLocalModelOnLaunch: true,
        launchAtLogin: false,
        hasCompletedOnboarding: false
    )
}
