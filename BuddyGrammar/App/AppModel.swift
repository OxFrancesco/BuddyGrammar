import AppKit
import Foundation
import Observation
import Speech
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let settingsWindowID = "settings-window"
    static let notesWindowID = "notes-window"
    #if DEBUG
    static let debugWindowID = "debug-window"
    #endif

    let settingsStore: SettingsStore
    let notesStore: NotesStore
    let keychainService: KeychainService
    let accessibilityService: AccessibilityService
    let appUpdateService: AppUpdateService
    let hotkeyService: HotkeyService
    let localModelStore: LocalModelStore
    let voiceAuthorizationService: VoiceAuthorizationService
    let voiceModelStore: VoiceModelStore
    let rewriteProviderController: RewriteProviderController
    let rewriteCoordinator: RewriteCoordinator
    let voiceInputCoordinator: VoiceInputCoordinator
    let menuBarStatus: MenuBarStatusModel

    var selectedProfileID: UUID?
    var selectedNoteID: UUID?
    var apiKeyDraft = ""
    var settingsErrorMessage: String?
    var appleSpeechAvailableForSelectedLocale: Bool?
    var openRouterModels: [OpenRouterModelSummary] = []
    var openRouterModelsAreLoading = false
    var openRouterModelsErrorMessage: String?
    private var environmentStateRevision = 0

    private let launchAtLoginService: LaunchAtLoginService
    private let clipboardService: ClipboardService
    private let eventSimulationService: EventSimulationService
    private var onboardingWindowController: NSWindowController?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private var utilityWindowCloseObserver: NSObjectProtocol?

    init() {
        let settingsStore = SettingsStore()
        let notesStore = NotesStore()
        let keychainService = KeychainService()
        let accessibilityService = AccessibilityService()
        let appUpdateService = AppUpdateService()
        let clipboardService = ClipboardService()
        let eventSimulationService = EventSimulationService()
        let menuBarStatus = MenuBarStatusModel()
        let localModelStore = LocalModelStore()
        let voiceAuthorizationService = VoiceAuthorizationService()
        let voiceModelStore = VoiceModelStore()
        let audioRecordingService = AudioRecordingService()
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
        let voiceInputCoordinator = VoiceInputCoordinator(
            settingsProvider: settingsStore,
            rewriteProvider: rewriteProviderController,
            clipboardService: clipboardService,
            eventSimulationService: eventSimulationService,
            voiceAuthorizationService: voiceAuthorizationService,
            audioRecordingService: audioRecordingService,
            voiceModelStore: voiceModelStore,
            menuBarStatus: menuBarStatus
        )

        self.settingsStore = settingsStore
        self.notesStore = notesStore
        self.keychainService = keychainService
        self.accessibilityService = accessibilityService
        self.appUpdateService = appUpdateService
        self.hotkeyService = hotkeyService
        self.localModelStore = localModelStore
        self.voiceAuthorizationService = voiceAuthorizationService
        self.voiceModelStore = voiceModelStore
        self.rewriteProviderController = rewriteProviderController
        self.launchAtLoginService = launchAtLoginService
        self.rewriteCoordinator = rewriteCoordinator
        self.voiceInputCoordinator = voiceInputCoordinator
        self.menuBarStatus = menuBarStatus
        self.clipboardService = clipboardService
        self.eventSimulationService = eventSimulationService
        self.selectedProfileID = settingsStore.profiles.first?.id
        self.selectedNoteID = notesStore.notes.first?.id
        self.apiKeyDraft = keychainService.loadAPIKey() ?? ""
        self.appleSpeechAvailableForSelectedLocale = nil

        hotkeyService.onHotKey = { [weak self] profileID in
            self?.runProfile(id: profileID)
        }
        hotkeyService.onVoiceHotKey = { [weak self] in
            self?.toggleVoiceInput()
        }
        hotkeyService.onNoteHotKey = { [weak self] noteID in
            self?.pasteNote(id: noteID)
        }
        settingsStore.onProfilesChanged = { [weak self] profiles in
            self?.registerHotkeys()
            if let selectedID = self?.selectedProfileID, !profiles.contains(where: { $0.id == selectedID }) {
                self?.selectedProfileID = profiles.first?.id
            }
        }
        settingsStore.onSettingsChanged = { [weak self] settings in
            self?.apply(settings: settings)
            self?.rewriteProviderController.apply(settings: settings)
            self?.registerHotkeys()
            self?.refreshVoiceSpeechAvailability()
        }
        notesStore.onNotesChanged = { [weak self] notes in
            self?.registerHotkeys()
            if let selectedID = self?.selectedNoteID, !notes.contains(where: { $0.id == selectedID }) {
                self?.selectedNoteID = notes.first?.id
            }
        }

        refreshVoiceSpeechAvailability()
    }

    var hasAPIKey: Bool {
        _ = environmentStateRevision
        return keychainService.hasAPIKey()
    }

    var accessibilityGranted: Bool {
        _ = environmentStateRevision
        return accessibilityService.isTrusted(prompt: false)
    }

    var microphonePermission: VoicePermissionState {
        _ = environmentStateRevision
        return voiceAuthorizationService.microphonePermission
    }

    var speechRecognitionPermission: VoicePermissionState {
        _ = environmentStateRevision
        return voiceAuthorizationService.speechRecognitionPermission
    }

    var appBundlePath: String {
        Bundle.main.bundlePath
    }

    var isRunningFromDerivedData: Bool {
        appBundlePath.contains("/DerivedData/")
    }

    func start() {
        registerHotkeys()
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

    func prepareToOpenUtilityWindow() {
        promoteForForegroundWindow()
    }

    func settingsWindowDidAppear() {
        configureSettingsWindows()
        focusSettingsWindowSoon()
    }

    func settingsWindowDidDisappear() {
        restoreAccessoryActivationIfPossible()
    }

    func utilityWindowDidAppear() {
        configureUtilityWindows()
        promoteForForegroundWindow()
    }

    func utilityWindowDidDisappear() {
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
        window.title = "Welcome to BuddyWrite"
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

    func openAppSupportFolder() {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshEnvironmentState() {
        environmentStateRevision += 1
    }

    func refreshVoiceSpeechAvailability() {
        let localeIdentifier = voiceLocaleIdentifier
        appleSpeechAvailableForSelectedLocale = nil

        Task { [weak self] in
            guard let self else { return }
            let available = await self.voiceModelStore.appleOnDeviceAvailable(for: localeIdentifier)
            await MainActor.run {
                guard self.voiceLocaleIdentifier == localeIdentifier else { return }
                self.appleSpeechAvailableForSelectedLocale = available
                self.refreshEnvironmentState()
            }
        }
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

    func loadOpenRouterModels(forceRefresh: Bool = false) async {
        guard !openRouterModelsAreLoading else { return }
        if !forceRefresh, !openRouterModels.isEmpty { return }

        openRouterModelsAreLoading = true
        openRouterModelsErrorMessage = nil
        defer { openRouterModelsAreLoading = false }

        do {
            openRouterModels = try await rewriteProviderController.openRouterModels(forceRefresh: forceRefresh)
        } catch {
            openRouterModelsErrorMessage = error.localizedDescription
        }
    }

    func runProfile(id: UUID) {
        guard let profile = settingsStore.profile(id: id) else { return }
        runProfile(profile)
    }

    func runProfile(_ profile: PromptProfile) {
        rewriteCoordinator.run(profile: profile, accessibilityService: accessibilityService)
    }

    func toggleVoiceInput() {
        voiceInputCoordinator.toggleDictation(accessibilityService: accessibilityService)
    }

    func addNote() {
        selectedNoteID = notesStore.addNote()
    }

    func deleteSelectedNote() {
        guard let selectedNoteID else { return }
        notesStore.removeNote(id: selectedNoteID)
    }

    func pasteSelectedNote() {
        guard let selectedNoteID else { return }
        pasteNote(id: selectedNoteID)
    }

    func pasteNote(id: UUID) {
        guard let note = notesStore.note(id: id) else { return }
        pasteNote(note)
    }

    func copyNoteToClipboard(_ note: NoteItem) {
        clipboardService.writeString(note.content)
        menuBarStatus.show(.success(message: "Note copied"))
        menuBarStatus.reset(after: .seconds(1.2))
    }

    func pasteNote(_ note: NoteItem) {
        guard !note.content.isEmpty else { return }

        Task { @MainActor in
            guard accessibilityService.isTrusted(prompt: true) else {
                menuBarStatus.show(.failure(message: "Accessibility access needed"))
                menuBarStatus.reset(after: .seconds(2.4))
                return
            }

            let snapshot = clipboardService.snapshot()
            clipboardService.writeString(note.content)
            do {
                try eventSimulationService.simulatePaste()
                try await Task.sleep(for: .milliseconds(180))
                clipboardService.restore(snapshot)
                menuBarStatus.show(.success(message: "Note pasted"))
                menuBarStatus.reset(after: .seconds(1.2))
            } catch {
                clipboardService.restore(snapshot)
                menuBarStatus.show(.failure(message: "Could not paste note"))
                menuBarStatus.reset(after: .seconds(2.4))
            }
        }
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

    func preloadVoiceFallbackModel() {
        voiceModelStore.preloadFallbackModel()
    }

    func setVoiceProfileID(_ profileID: UUID?) {
        settingsStore.appSettings.voiceProfileID = profileID
    }

    func setVoiceLocaleIdentifier(_ localeIdentifier: String) {
        settingsStore.appSettings.voiceLocaleIdentifier = localeIdentifier
        refreshVoiceSpeechAvailability()
    }

    func setVoiceHotkey(_ hotkey: HotkeyDescriptor?) {
        settingsStore.appSettings.voiceHotkey = hotkey
    }

    func requestVoicePermissions() {
        Task { @MainActor in
            let microphoneGranted = modelRequiresMicrophonePrompt
                ? await voiceAuthorizationService.requestMicrophoneAccess()
                : voiceAuthorizationService.microphonePermission.isAuthorized

            guard microphoneGranted else {
                refreshEnvironmentState()
                return
            }

            let needsSpeechPrompt = await voiceModelStore.appleOnDeviceAvailable(for: voiceLocaleIdentifier)
            if needsSpeechPrompt, modelRequiresSpeechPrompt {
                _ = await voiceAuthorizationService.requestSpeechRecognitionAccess()
            }
            refreshEnvironmentState()
        }
    }

    func requestMicrophonePermission() {
        Task { @MainActor in
            _ = await voiceAuthorizationService.requestMicrophoneAccess()
            refreshEnvironmentState()
        }
    }

    func requestSpeechRecognitionPermission() {
        guard speechRecognitionRequiredForDictation else { return }

        Task { @MainActor in
            _ = await voiceAuthorizationService.requestSpeechRecognitionAccess()
            refreshEnvironmentState()
        }
    }

    func openMicrophoneSettings() {
        voiceAuthorizationService.openMicrophoneSettings()
    }

    func openSpeechRecognitionSettings() {
        voiceAuthorizationService.openSpeechRecognitionSettings()
    }

    var voicePermissionsGranted: Bool {
        microphonePermission.isAuthorized && (
            !speechRecognitionRequiredForDictation || speechRecognitionPermission.isAuthorized
        )
    }

    var voicePermissionsRequested: Bool {
        microphonePermission != .notDetermined || (
            speechRecognitionRequiredForDictation && speechRecognitionPermission != .notDetermined
        )
    }

    var speechRecognitionRequiredForDictation: Bool {
        appleSpeechAvailableForSelectedLocale != false
    }

    func deleteSelectedPersonality() {
        guard let selectedProfileID else { return }
        settingsStore.removeProfile(id: selectedProfileID)
    }

    func moveSelectedPersonality(_ direction: MoveDirection) {
        guard let selectedProfileID else { return }
        settingsStore.moveProfile(id: selectedProfileID, direction: direction)
    }

    func noteHotkeyConflictLabel(for noteID: UUID, hotkey: HotkeyDescriptor?) -> String? {
        guard let hotkey else { return nil }

        if let note = notesStore.hotkeyConflict(for: noteID, hotkey: hotkey) {
            return note.displayTitle
        }

        if let profile = settingsStore.profiles.first(where: { $0.isEnabled && $0.hotkey == hotkey }) {
            return profile.name
        }

        if settingsStore.appSettings.voiceHotkey == hotkey {
            return "Dictation"
        }

        return nil
    }

    func profileHotkeyConflictLabel(for profileID: UUID, hotkey: HotkeyDescriptor?) -> String? {
        guard let hotkey else { return nil }

        if let profile = settingsStore.hotkeyConflict(for: profileID, hotkey: hotkey) {
            return profile.name
        }

        if let note = notesStore.notes.first(where: { $0.hotkey == hotkey }) {
            return note.displayTitle
        }

        if settingsStore.appSettings.voiceHotkey == hotkey {
            return "Dictation"
        }

        return nil
    }

    #if DEBUG
    func copyDebugDiagnostics() {
        clipboardService.writeString(debugDiagnosticsText)
        menuBarStatus.show(.success(message: "Debug info copied"))
        menuBarStatus.reset(after: .seconds(1.2))
    }

    var debugDiagnosticsText: String {
        let localStatuses = LocalModelID.allCases
            .map { "\($0.title): \(localModelStore.status(for: $0).state.title)" }
            .joined(separator: "\n")

        return """
        BuddyWrite Diagnostics
        Version: \(appUpdateService.currentVersionDescription)
        Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")
        Path: \(appBundlePath)
        DerivedData: \(isRunningFromDerivedData)
        Accessibility: \(accessibilityGranted ? "Granted" : "Missing")
        Microphone: \(microphonePermission.title)
        Speech Recognition: \(speechRecognitionPermission.title)
        Output Mode: \(settingsStore.appSettings.outputMode.title)
        Provider: \(currentProviderDescription)
        API Key Saved: \(hasAPIKey)
        Rewrite Status: \(rewriteCoordinator.statusMessage)
        Rewrite Error: \(rewriteCoordinator.lastErrorMessage ?? "None")
        Local Model Error: \(localModelStore.lastErrorMessage ?? "None")
        Voice Error: \(voiceModelStore.lastErrorMessage ?? "None")
        Notes: \(notesStore.notes.count)
        Profiles: \(settingsStore.profiles.count)
        Local Models:
        \(localStatuses)
        """
    }
    #endif

    private func apply(settings: AppSettings) {
        do {
            try launchAtLoginService.setEnabled(settings.launchAtLogin)
            settingsErrorMessage = nil
        } catch {
            settingsErrorMessage = "Could not update launch at login: \(error.localizedDescription)"
        }
    }

    private func registerHotkeys() {
        hotkeyService.register(
            profiles: settingsStore.enabledProfilesWithHotkeys(),
            voiceHotkey: settingsStore.appSettings.voiceHotkey,
            notes: notesStore.notesWithHotkeys()
        )
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
        let hasVisibleForegroundWindow = NSApp.windows.contains { window in
            (isSettingsWindow(window) || isUtilityWindow(window)) && window.isVisible
        }
        let hasVisibleOnboardingWindow = onboardingWindowController?.window?.isVisible == true

        guard !hasVisibleForegroundWindow, !hasVisibleOnboardingWindow else {
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

    private func configureUtilityWindows() {
        for window in NSApp.windows where isUtilityWindow(window) {
            window.styleMask.insert(.resizable)
            window.collectionBehavior.formUnion([.fullScreenPrimary, .moveToActiveSpace])
            installUtilityWindowCloseObserver(for: window)
        }
    }

    private func isUtilityWindow(_ window: NSWindow) -> Bool {
        let identifier = window.identifier?.rawValue
        if identifier == Self.notesWindowID {
            return true
        }
        #if DEBUG
        if identifier == Self.debugWindowID {
            return true
        }
        #endif

        let title = window.title.localizedLowercase
        if title.contains("notes") {
            return true
        }
        #if DEBUG
        if title.contains("debug") {
            return true
        }
        #endif
        return false
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

    private func installUtilityWindowCloseObserver(for window: NSWindow) {
        if let utilityWindowCloseObserver {
            NotificationCenter.default.removeObserver(utilityWindowCloseObserver)
        }

        utilityWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.utilityWindowCloseObserver = nil
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

    var selectedVoiceProfile: PromptProfile {
        if let voiceProfileID = settingsStore.appSettings.voiceProfileID,
           let voiceProfile = settingsStore.profile(id: voiceProfileID) {
            return voiceProfile
        }

        return settingsStore.profile(id: PromptProfile.grammarProfileID) ?? PromptProfile.standard
    }

    var voiceLocaleIdentifier: String {
        settingsStore.appSettings.voiceLocaleIdentifier ?? Locale.autoupdatingCurrent.identifier
    }

    var voiceHotkey: HotkeyDescriptor? {
        settingsStore.appSettings.voiceHotkey
    }

    var voiceFallbackStatus: VoiceModelStatus {
        voiceModelStore.status
    }

    var availableVoiceLocales: [VoiceLocaleOption] {
        VoiceLocaleOption.defaultOptions(currentIdentifier: voiceLocaleIdentifier)
    }

    func voiceHotkeyConflictLabel(for hotkey: HotkeyDescriptor?) -> String? {
        guard let hotkey else { return nil }
        if let conflict = settingsStore.profiles.first(where: { $0.isEnabled && $0.hotkey == hotkey }) {
            return conflict.name
        }
        return nil
    }

    private var modelRequiresMicrophonePrompt: Bool {
        !voiceAuthorizationService.microphonePermission.isAuthorized
    }

    private var modelRequiresSpeechPrompt: Bool {
        !voiceAuthorizationService.speechRecognitionPermission.isAuthorized
    }
}

struct VoiceLocaleOption: Identifiable, Hashable {
    let id: String
    let title: String

    static func defaultOptions(currentIdentifier: String) -> [VoiceLocaleOption] {
        let supported = SFSpeechRecognizer.supportedLocales()
            .map { locale in
                let identifier = locale.identifier
                let localizedName = Locale.autoupdatingCurrent.localizedString(forIdentifier: identifier) ?? identifier
                return VoiceLocaleOption(id: identifier, title: localizedName)
            }
            .sorted { (lhs: VoiceLocaleOption, rhs: VoiceLocaleOption) in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        if supported.contains(where: { $0.id == currentIdentifier }) {
            return supported
        }

        let currentName = Locale.autoupdatingCurrent.localizedString(forIdentifier: currentIdentifier) ?? currentIdentifier
        return [VoiceLocaleOption(id: currentIdentifier, title: "\(currentName) (System)") ] + supported
    }
}
