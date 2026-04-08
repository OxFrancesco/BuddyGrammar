import Foundation
import Observation

@MainActor
@Observable
final class RewriteProviderController {
    private let settingsStore: SettingsStore
    private let keychainService: KeychainService
    private let openRouterClient: OpenRouterClient

    let localModelStore: LocalModelStore

    init(
        settingsStore: SettingsStore,
        keychainService: KeychainService,
        openRouterClient: OpenRouterClient,
        localModelStore: LocalModelStore
    ) {
        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.openRouterClient = openRouterClient
        self.localModelStore = localModelStore
    }

    func start() {
        apply(settings: settingsStore.appSettings)
    }

    func apply(settings: AppSettings) {
        localModelStore.apply(settings: settings)
    }

    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        let engine = currentEngine(for: settingsStore.appSettings.rewriteProvider)
        return try await engine.rewrite(request)
    }

    private func currentEngine(for provider: RewriteProvider) -> any RewriteEngine {
        switch provider {
        case .openRouter(let modelID):
            OpenRouterRewriteEngine(
                client: openRouterClient,
                apiKey: keychainService.loadAPIKey(),
                modelID: modelID
            )
        case .local(let modelID):
            LocalMLXRewriteEngine(localModelStore: localModelStore, modelID: modelID)
        }
    }
}
