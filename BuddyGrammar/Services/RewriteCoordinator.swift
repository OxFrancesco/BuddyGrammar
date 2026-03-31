import Foundation
import Observation

@MainActor
@Observable
final class RewriteCoordinator {
    var statusMessage = "Ready"
    var lastErrorMessage: String?
    var isProcessing = false

    private let settingsStore: SettingsStore
    private let keychainService: KeychainService
    private let selectionService: SelectionService
    private let clipboardService: ClipboardService
    private let eventSimulationService: EventSimulationService
    private let openRouterClient: OpenRouterClient
    private let overlayManager: OverlayManager

    init(
        settingsStore: SettingsStore,
        keychainService: KeychainService,
        selectionService: SelectionService,
        clipboardService: ClipboardService,
        eventSimulationService: EventSimulationService,
        openRouterClient: OpenRouterClient,
        overlayManager: OverlayManager
    ) {
        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.selectionService = selectionService
        self.clipboardService = clipboardService
        self.eventSimulationService = eventSimulationService
        self.openRouterClient = openRouterClient
        self.overlayManager = overlayManager
    }

    func run(profile: PromptProfile, accessibilityService: AccessibilityService) {
        guard !isProcessing else {
            presentFailure(.busy)
            return
        }

        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }

            guard accessibilityService.isTrusted(prompt: true) else {
                presentFailure(.accessibilityPermissionDenied)
                return
            }

            guard let apiKey = keychainService.loadAPIKey(), !apiKey.isEmpty else {
                presentFailure(.missingAPIKey)
                return
            }

            do {
                overlayManager.present(.capture(profileName: profile.name), motionMode: settingsStore.appSettings.overlayMotionMode)
                let selectedText = try await selectionService.captureSelectedText()
                overlayManager.present(.sending(profileName: profile.name), motionMode: settingsStore.appSettings.overlayMotionMode)

                let result = try await openRouterClient.rewrite(
                    RewriteRequest(profile: profile, selectedText: selectedText),
                    apiKey: apiKey
                )

                switch settingsStore.appSettings.outputMode {
                case .replaceSelection:
                    try await pasteReplacement(result.rewrittenText)
                    statusMessage = "Replaced selection with \(profile.name.lowercased()) output."
                    overlayManager.present(.success(profileName: profile.name, message: "Selection replaced"), motionMode: settingsStore.appSettings.overlayMotionMode)
                case .copyToClipboard:
                    clipboardService.writeString(result.rewrittenText)
                    statusMessage = "Copied \(profile.name.lowercased()) output to the clipboard."
                    overlayManager.present(.success(profileName: profile.name, message: "Copied to clipboard"), motionMode: settingsStore.appSettings.overlayMotionMode)
                }

                lastErrorMessage = nil
                overlayManager.dismiss(after: .seconds(1.6))
            } catch let error as RewriteFailure {
                presentFailure(error)
            } catch {
                presentFailure(.network(error.localizedDescription))
            }
        }
    }

    private func pasteReplacement(_ string: String) async throws {
        let snapshot = clipboardService.snapshot()
        clipboardService.writeString(string)
        do {
            try eventSimulationService.simulatePaste()
            try await Task.sleep(for: .milliseconds(180))
            clipboardService.restore(snapshot)
        } catch {
            clipboardService.restore(snapshot)
            throw RewriteFailure.pasteFailed
        }
    }

    private func presentFailure(_ failure: RewriteFailure) {
        let message = failure.errorDescription ?? "Something went wrong."
        statusMessage = message
        lastErrorMessage = message
        overlayManager.present(.failure(message: message), motionMode: settingsStore.appSettings.overlayMotionMode)
        overlayManager.dismiss(after: .seconds(2.4))
    }
}
