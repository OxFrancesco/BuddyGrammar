import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let settingsWindowID = "settings-window"

    let settingsStore: SettingsStore
    let keychainService: KeychainService
    let accessibilityService: AccessibilityService
    let appUpdateService: AppUpdateService
    let hotkeyService: HotkeyService
    let localModelStore: LocalModelStore
    let rewriteProviderController: RewriteProviderController
    let rewriteCoordinator: RewriteCoordinator
    let menuBarStatus: MenuBarStatusModel

    var selectedProfileID: UUID?
    var apiKeyDraft = ""
    var settingsErrorMessage: String?
    private var environmentStateRevision = 0

    private let launchAtLoginService: LaunchAtLoginService
    private var onboardingWindowController: NSWindowController?
    private var settingsWindowCloseObserver: NSObjectProtocol?

    init() {
        let settingsStore = SettingsStore()
        let keychainService = KeychainService()
        let accessibilityService = AccessibilityService()
        let appUpdateService = AppUpdateService()
        let clipboardService = ClipboardService()
        let eventSimulationService = EventSimulationService()
        let menuBarStatus = MenuBarStatusModel()
        let localModelStore = LocalModelStore()
        let selectionService = SelectionService(
            accessibilityService: accessibilityService,
            clipboardService: clipboardService,
            eventSimulationService: eventSimulationService
        )
        let openRouterClient = OpenRouterClient()
        let rewriteProviderController = RewriteProviderController(
            settingsStore: settingsStore,
            keychainService: keychainService,
            openRouterClient: openRouterClient,
            localModelStore: localModelStore
        )
        let hotkeyService = HotkeyService()
        let launchAtLoginService = LaunchAtLoginService()
        let rewriteCoordinator = RewriteCoordinator(
            settingsStore: settingsStore,
            selectionService: selectionService,
            clipboardService: clipboardService,
            eventSimulationService: eventSimulationService,
            rewriteProviderController: rewriteProviderController,
            menuBarStatus: menuBarStatus
        )

        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.accessibilityService = accessibilityService
        self.appUpdateService = appUpdateService
        self.hotkeyService = hotkeyService
        self.localModelStore = localModelStore
        self.rewriteProviderController = rewriteProviderController
        self.launchAtLoginService = launchAtLoginService
        self.rewriteCoordinator = rewriteCoordinator
        self.menuBarStatus = menuBarStatus
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
            self?.rewriteProviderController.apply(settings: settings)
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
        rewriteProviderController.start()
        restoreAccessoryActivationIfPossible()
        if !settingsStore.appSettings.hasCompletedOnboarding {
            openOnboarding()
        }
    }

    func prepareToOpenSettingsWindow() {
        promoteForForegroundWindow()
    }

    func settingsWindowDidAppear() {
        configureSettingsWindows()
        focusSettingsWindowSoon()
    }

    func settingsWindowDidDisappear() {
        restoreAccessoryActivationIfPossible()
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
        promoteForForegroundWindow()
    }

    func completeOnboarding() {
        settingsStore.markOnboardingComplete()
        onboardingWindowController?.close()
        onboardingWindowController = nil
        restoreAccessoryActivationIfPossible()
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

    func checkForUpdates() {
        appUpdateService.checkForUpdates()
    }

    func openReleasesPage() {
        appUpdateService.openReleasesPage()
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

    func addPersonality(template: PersonalityTemplate = .blankCustom) {
        selectedProfileID = settingsStore.addProfile(template: template)
    }

    func setRewriteProviderKind(_ providerKind: RewriteProviderKind) {
        var settings = settingsStore.appSettings
        switch providerKind {
        case .openRouter:
            let modelID = settings.rewriteProvider.openRouterModelID ?? OpenRouterModel.defaultID
            settings.rewriteProvider = .openRouter(modelID: modelID)
        case .local:
            settings.rewriteProvider = .local(modelID: settings.selectedLocalModel)
        }
        settingsStore.appSettings = settings
    }

    func setSelectedLocalModel(_ modelID: LocalModelID) {
        var settings = settingsStore.appSettings
        settings.selectedLocalModel = modelID
        if settings.rewriteProvider.kind == .local {
            settings.rewriteProvider = .local(modelID: modelID)
        }
        settingsStore.appSettings = settings
    }

    func setPreloadLocalModelOnLaunch(_ preload: Bool) {
        settingsStore.appSettings.preloadLocalModelOnLaunch = preload
    }

    func preloadSelectedLocalModel() {
        localModelStore.preload(modelID: settingsStore.appSettings.selectedLocalModel)
    }

    func deleteSelectedPersonality() {
        guard let selectedProfileID else { return }
        settingsStore.removeProfile(id: selectedProfileID)
    }

    func moveSelectedPersonality(_ direction: MoveDirection) {
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

    private func focusSettingsWindowSoon() {
        focusSettingsWindow()
        DispatchQueue.main.async { [weak self] in
            self?.focusSettingsWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.focusSettingsWindow()
        }
    }

    private func focusSettingsWindow() {
        for window in NSApp.windows where isSettingsWindow(window) {
            configureSettingsWindow(window)
            promoteForForegroundWindow()
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == Self.settingsWindowID {
            return true
        }

        let title = window.title.localizedLowercase
        return title.contains("settings") || title.contains("preferences")
    }

    private func promoteForForegroundWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreAccessoryActivationIfPossible() {
        let hasVisibleSettingsWindow = NSApp.windows.contains { window in
            isSettingsWindow(window) && window.isVisible
        }
        let hasVisibleOnboardingWindow = onboardingWindowController?.window?.isVisible == true

        guard !hasVisibleSettingsWindow, !hasVisibleOnboardingWindow else {
            return
        }

        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func configureSettingsWindows() {
        for window in NSApp.windows where isSettingsWindow(window) {
            configureSettingsWindow(window)
        }
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(Self.settingsWindowID)
        window.styleMask.insert(.resizable)
        window.collectionBehavior.formUnion([.fullScreenPrimary, .moveToActiveSpace])
        installSettingsWindowCloseObserver(for: window)
    }

    private func installSettingsWindowCloseObserver(for window: NSWindow) {
        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
        }

        settingsWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.settingsWindowCloseObserver = nil
                DispatchQueue.main.async {
                    self.restoreAccessoryActivationIfPossible()
                }
            }
        }
    }

    var rewriteProviderKind: RewriteProviderKind {
        settingsStore.appSettings.rewriteProvider.kind
    }

    var selectedLocalModel: LocalModelID {
        settingsStore.appSettings.selectedLocalModel
    }

    var preloadLocalModelOnLaunch: Bool {
        settingsStore.appSettings.preloadLocalModelOnLaunch
    }

    var selectedLocalModelStatus: LocalModelStatus {
        localModelStore.status(for: selectedLocalModel)
    }

    var usesLocalProvider: Bool {
        rewriteProviderKind == .local
    }

    var currentProviderDescription: String {
        settingsStore.appSettings.rewriteProvider.modelLabel
    }
}
