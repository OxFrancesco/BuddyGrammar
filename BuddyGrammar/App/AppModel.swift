import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    let settingsStore: SettingsStore
    let keychainService: KeychainService
    let accessibilityService: AccessibilityService
    let hotkeyService: HotkeyService
    let rewriteCoordinator: RewriteCoordinator

    var selectedProfileID: UUID?
    var apiKeyDraft = ""
    var settingsErrorMessage: String?
    private var environmentStateRevision = 0

    private let launchAtLoginService: LaunchAtLoginService
    private var onboardingWindowController: NSWindowController?

    init() {
        let settingsStore = SettingsStore()
        let keychainService = KeychainService()
        let accessibilityService = AccessibilityService()
        let clipboardService = ClipboardService()
        let eventSimulationService = EventSimulationService()
        let overlayModel = OverlayModel()
        let overlayManager = OverlayManager(model: overlayModel)
        let selectionService = SelectionService(
            accessibilityService: accessibilityService,
            clipboardService: clipboardService,
            eventSimulationService: eventSimulationService
        )
        let openRouterClient = OpenRouterClient()
        let hotkeyService = HotkeyService()
        let launchAtLoginService = LaunchAtLoginService()
        let rewriteCoordinator = RewriteCoordinator(
            settingsStore: settingsStore,
            keychainService: keychainService,
            selectionService: selectionService,
            clipboardService: clipboardService,
            eventSimulationService: eventSimulationService,
            openRouterClient: openRouterClient,
            overlayManager: overlayManager
        )

        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.accessibilityService = accessibilityService
        self.hotkeyService = hotkeyService
        self.launchAtLoginService = launchAtLoginService
        self.rewriteCoordinator = rewriteCoordinator
        self.selectedProfileID = settingsStore.profiles.first?.id
        self.apiKeyDraft = keychainService.loadAPIKey() ?? ""

        hotkeyService.onHotKey = { [weak self] profileID in
            self?.runProfile(id: profileID)
        }
        settingsStore.onProfilesChanged = { [weak self] profiles in
            self?.hotkeyService.register(profiles: profiles)
            if let selectedID = self?.selectedProfileID, !profiles.contains(where: { $0.id == selectedID }) {
                self?.selectedProfileID = profiles.first?.id
            }
        }
        settingsStore.onSettingsChanged = { [weak self] settings in
            self?.apply(settings: settings)
        }
    }

    var hasAPIKey: Bool {
        _ = environmentStateRevision
        return keychainService.hasAPIKey()
    }

    var accessibilityGranted: Bool {
        _ = environmentStateRevision
        return accessibilityService.isTrusted(prompt: false)
    }

    var appBundlePath: String {
        Bundle.main.bundlePath
    }

    var isRunningFromDerivedData: Bool {
        appBundlePath.contains("/DerivedData/")
    }

    func start() {
        hotkeyService.register(profiles: settingsStore.enabledProfilesWithHotkeys())
        apply(settings: settingsStore.appSettings)
        if !settingsStore.appSettings.hasCompletedOnboarding {
            openOnboarding()
        }
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func openOnboarding() {
        let rootView = OnboardingView(model: self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to BuddyGrammar"
        window.minSize = NSSize(width: 760, height: 560)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func completeOnboarding() {
        settingsStore.markOnboardingComplete()
        onboardingWindowController?.close()
        onboardingWindowController = nil
    }

    func openAccessibilitySettings() {
        accessibilityService.openAccessibilitySettings()
    }

    func revealCurrentAppInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appBundlePath)
    }

    func refreshEnvironmentState() {
        environmentStateRevision += 1
    }

    func saveAPIKey() {
        do {
            let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                keychainService.deleteAPIKey()
            } else {
                try keychainService.saveAPIKey(trimmed)
            }
            settingsErrorMessage = nil
        } catch {
            settingsErrorMessage = error.localizedDescription
        }
        refreshEnvironmentState()
    }

    func runProfile(id: UUID) {
        guard let profile = settingsStore.profile(id: id) else { return }
        runProfile(profile)
    }

    func runProfile(_ profile: PromptProfile) {
        rewriteCoordinator.run(profile: profile, accessibilityService: accessibilityService)
    }

    func addProfile() {
        selectedProfileID = settingsStore.addProfile()
    }

    func deleteSelectedProfile() {
        guard let selectedProfileID else { return }
        settingsStore.removeProfile(id: selectedProfileID)
    }

    func moveSelectedProfile(_ direction: MoveDirection) {
        guard let selectedProfileID else { return }
        settingsStore.moveProfile(id: selectedProfileID, direction: direction)
    }

    private func apply(settings: AppSettings) {
        do {
            try launchAtLoginService.setEnabled(settings.launchAtLogin)
            settingsErrorMessage = nil
        } catch {
            settingsErrorMessage = "Could not update launch at login: \(error.localizedDescription)"
        }
    }
}
