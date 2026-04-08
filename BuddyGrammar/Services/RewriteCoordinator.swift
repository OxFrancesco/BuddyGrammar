import Foundation
import Observation

@MainActor
@Observable
final class RewriteCoordinator {
    var statusMessage = "Ready"
    var lastErrorMessage: String?
    var isProcessing = false

    private let settingsStore: SettingsStore
    private let selectionService: SelectionService
    private let clipboardService: ClipboardService
    private let eventSimulationService: EventSimulationService
    private let rewriteProviderController: RewriteProviderController
    private let menuBarStatus: MenuBarStatusModel

    init(
        settingsStore: SettingsStore,
        selectionService: SelectionService,
        clipboardService: ClipboardService,
        eventSimulationService: EventSimulationService,
        rewriteProviderController: RewriteProviderController,
        menuBarStatus: MenuBarStatusModel
    ) {
        self.settingsStore = settingsStore
        self.selectionService = selectionService
        self.clipboardService = clipboardService
        self.eventSimulationService = eventSimulationService
        self.rewriteProviderController = rewriteProviderController
        self.menuBarStatus = menuBarStatus
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

            do {
                statusMessage = "Reading the current selection..."
                menuBarStatus.show(.capture(profileName: profile.name))
                let selectedText = try await selectionService.captureSelectedText()
                statusMessage = "Fixing your text with \(profile.name)..."
                menuBarStatus.show(.sending(profileName: profile.name))

                let result = try await rewriteProviderController.rewrite(
                    RewriteRequest(profile: profile, selectedText: selectedText)
                )

                switch settingsStore.appSettings.outputMode {
                case .replaceSelection:
                    try await pasteReplacement(result.rewrittenText)
                    statusMessage = "Replaced selection with \(profile.name.lowercased()) output."
                    menuBarStatus.show(.success(message: "Selection replaced"))
                case .copyToClipboard:
                    clipboardService.writeString(result.rewrittenText)
                    statusMessage = "Copied \(profile.name.lowercased()) output to the clipboard."
                    menuBarStatus.show(.success(message: "Copied to clipboard"))
                }

                lastErrorMessage = nil
                menuBarStatus.reset(after: .seconds(1.6))
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
        menuBarStatus.show(.failure(message: message))
        menuBarStatus.reset(after: .seconds(2.4))
    }
}
