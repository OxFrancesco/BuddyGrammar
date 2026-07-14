import BuddyGrammarKit
import Foundation
import Observation
import OSLog
import UIKit

let appDictationLog = Logger(
    subsystem: "com.francescooddo.BuddyGrammar",
    category: "app.dictation"
)

enum AppTab: Hashable {
    case home
    case dictation
    case settings
}

enum DictationPhase: Equatable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case correcting
    case ready

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isProcessing: Bool {
        self == .transcribing || self == .correcting
    }
}

struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct AppNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case information
    }

    let id = UUID()
    let message: String
    let kind: Kind
}

@MainActor
@Observable
final class IOSAppModel {
    var settings: BuddyGrammarSettings
    var pendingTranscript: PendingTranscript?
    var transcriptDraft = ""
    var dictationPhase: DictationPhase = .idle {
        didSet { syncCompanionStatus() }
    }
    var selectedTab: AppTab = .home
    var detectedLanguageCode: String?
    var alert: AppAlert?
    var notice: AppNotice?
    private(set) var keyboardDictationSessionID: UUID?
    let isSharedContainerReady: Bool
    let companion: DictationCompanionController

    private let preferences: SharedPreferences?
    private let audioRecorder: IOSAudioRecorder
    private let transcriptionClient: ElevenLabsTranscriptionClient
    private let correctionClient: OpenRouterCorrectionClient
    private var keyboardStopMonitorTask: Task<Void, Never>?
    private var companionStartTask: Task<Void, Never>?
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    init(
        preferences: SharedPreferences? = nil,
        audioRecorder: IOSAudioRecorder = IOSAudioRecorder(),
        transcriptionClient: ElevenLabsTranscriptionClient = ElevenLabsTranscriptionClient(),
        correctionClient: OpenRouterCorrectionClient = OpenRouterCorrectionClient()
    ) {
        let sharedPreferences = preferences ?? SharedPreferences()
        isSharedContainerReady = sharedPreferences != nil
        self.preferences = sharedPreferences
        companion = DictationCompanionController(preferences: sharedPreferences)
        self.audioRecorder = audioRecorder
        self.transcriptionClient = transcriptionClient
        self.correctionClient = correctionClient

        var loadedSettings = sharedPreferences?.loadSettings() ?? .default
        var loadedTranscript = sharedPreferences?.loadPendingTranscript()

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--reset-onboarding") {
            loadedSettings = .default
            loadedTranscript = nil
            try? sharedPreferences?.saveSettings(loadedSettings)
            sharedPreferences?.clearPendingTranscript()
        }

        if arguments.contains("--ui-testing") || arguments.contains("--uitesting") {
            loadedSettings.hasCompletedOnboarding = true
            loadedSettings.hasAcceptedCloudProcessing = true
            loadedTranscript = PendingTranscript(
                text: "This sample is ready to insert from the BuddyGrammar keyboard."
            )
            try? sharedPreferences?.saveSettings(loadedSettings)
            if let loadedTranscript {
                try? sharedPreferences?.savePendingTranscript(loadedTranscript)
            }
        } else if arguments.contains("--skip-onboarding") {
            loadedSettings.hasCompletedOnboarding = true
            try? sharedPreferences?.saveSettings(loadedSettings)
        }

        #endif

        settings = loadedSettings
        pendingTranscript = loadedTranscript
        transcriptDraft = loadedTranscript?.text ?? ""

        if !isSharedContainerReady {
            alert = AppAlert(
                title: "Keyboard sharing unavailable",
                message: "BuddyGrammar could not open its shared App Group. Reinstall the signed app before saving a transcript for the keyboard."
            )
        }

        companion.onStartRequested = { [weak self] in
            self?.handleCompanionStartSignal()
        }
        companion.onStopRequested = { [weak self] in
            self?.handleCompanionStopSignal()
        }
        if settings.enablesQuickDictation, settings.hasCompletedOnboarding {
            companion.setEnabled(true)
        }
    }

    var isCloudReady: Bool {
        isSharedContainerReady
            && settings.hasAcceptedCloudProcessing
    }

    var isKeyboardDictationActive: Bool {
        keyboardDictationSessionID != nil
            && (dictationPhase.isRecording || dictationPhase.isProcessing)
    }

    func refresh() {
        if let preferences {
            settings = preferences.loadSettings()
            pendingTranscript = preferences.loadPendingTranscript()
            if transcriptDraft.isEmpty {
                transcriptDraft = pendingTranscript?.text ?? ""
            }
        }
    }

    func completeOnboarding(acceptsCloudProcessing: Bool) {
        settings.hasAcceptedCloudProcessing = acceptsCloudProcessing
        settings.hasCompletedOnboarding = true
        persistSettings(successMessage: nil)
    }

    func updateSettings(
        modelID: String,
        usesAutomaticModelUpdates: Bool,
        correctionInstruction: String,
        autoCorrectDictation: Bool,
        automaticallyCorrectWords: Bool,
        correctionUndoDuration: TimeInterval,
        acceptsCloudProcessing: Bool
    ) {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = correctionInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (usesAutomaticModelUpdates || !trimmedModelID.isEmpty),
              !trimmedInstruction.isEmpty else {
            showAlert(
                title: "Check correction settings",
                message: "The OpenRouter model and correction instructions cannot be empty."
            )
            return
        }

        settings.usesAutomaticModelUpdates = usesAutomaticModelUpdates
        settings.openRouterModelID = usesAutomaticModelUpdates
            ? BuddyGrammarConfiguration.defaultOpenRouterModelID
            : trimmedModelID
        settings.correctionInstruction = trimmedInstruction
        settings.autoCorrectDictation = autoCorrectDictation
        settings.automaticallyCorrectWords = automaticallyCorrectWords
        settings.correctionUndoDuration = BuddyGrammarSettings.clampedUndoDuration(
            correctionUndoDuration
        )
        settings.hasAcceptedCloudProcessing = acceptsCloudProcessing
        persistSettings(successMessage: "Preferences saved")
    }

    func startDictation(keyboardSessionID: UUID? = nil) async {
        guard settings.hasAcceptedCloudProcessing else {
            showAlert(
                title: "Cloud processing is off",
                message: "Allow cloud processing in Settings before sending audio to ElevenLabs."
            )
            return
        }

        do {
            let startedAt = try await audioRecorder.start()
            dictationPhase = .recording(startedAt: startedAt)
            detectedLanguageCode = nil
            self.keyboardDictationSessionID = keyboardSessionID
            if let keyboardSessionID {
                let session = try preferences?.updateKeyboardDictationSession(
                    id: keyboardSessionID,
                    phase: .recording
                )
                guard session != nil else {
                    audioRecorder.cancel()
                    self.keyboardDictationSessionID = nil
                    dictationPhase = transcriptDraft.isEmpty ? .idle : .ready
                    throw SharedContainerError.unavailable
                }
                monitorKeyboardStopRequest(sessionID: keyboardSessionID)
            }
        } catch {
            dictationPhase = .idle
            if let keyboardSessionID {
                _ = try? preferences?.updateKeyboardDictationSession(
                    id: keyboardSessionID,
                    phase: .failed,
                    errorMessage: error.localizedDescription
                )
            }
            self.keyboardDictationSessionID = nil
            showAlert(title: "Couldn’t start recording", message: error.localizedDescription)
        }
    }

    func finishDictation() async {
        guard dictationPhase.isRecording else { return }
        let keyboardSessionID = self.keyboardDictationSessionID
        keyboardStopMonitorTask?.cancel()
        keyboardStopMonitorTask = nil
        if let keyboardSessionID {
            beginBackgroundProcessing()
            _ = try? preferences?.updateKeyboardDictationSession(
                id: keyboardSessionID,
                phase: .transcribing
            )
        }
        defer {
            endBackgroundProcessing()
            self.keyboardDictationSessionID = nil
        }

        do {
            let recordingURL = try audioRecorder.stop()
            defer { try? FileManager.default.removeItem(at: recordingURL) }

            dictationPhase = .transcribing
            let audioData = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: recordingURL)
            }.value
            guard let clientID = preferences?.installationIdentifier() else {
                throw SharedContainerError.unavailable
            }
            let transcript = try await transcriptionClient.transcribe(
                audioData: audioData,
                clientID: clientID
            )

            detectedLanguageCode = transcript.languageCode
            var finalText = transcript.text
            var correctionFailure: Error?

            if settings.autoCorrectDictation {
                dictationPhase = .correcting
                do {
                    finalText = try await correctionClient.correct(
                        text: finalText,
                        clientID: clientID,
                        modelID: settings.activeOpenRouterModelID,
                        instruction: settings.correctionInstruction
                    )
                } catch {
                    correctionFailure = error
                }
            }

            transcriptDraft = finalText
            try savePendingTranscript(finalText)
            if let keyboardSessionID {
                try preferences?.updateKeyboardDictationSession(
                    id: keyboardSessionID,
                    phase: .ready,
                    transcript: finalText
                )
            }
            dictationPhase = .ready

            if let correctionFailure {
                showNotice(
                    "Transcript saved without correction: \(correctionFailure.localizedDescription)",
                    kind: .information
                )
            } else {
                showNotice("Ready in the BuddyGrammar keyboard", kind: .success)
            }
        } catch {
            if let keyboardSessionID {
                _ = try? preferences?.updateKeyboardDictationSession(
                    id: keyboardSessionID,
                    phase: .failed,
                    errorMessage: error.localizedDescription
                )
            }
            dictationPhase = transcriptDraft.isEmpty ? .idle : .ready
            showAlert(title: "Dictation failed", message: error.localizedDescription)
        }
    }

    func cancelRecording() {
        let keyboardSessionID = self.keyboardDictationSessionID
        keyboardStopMonitorTask?.cancel()
        keyboardStopMonitorTask = nil
        audioRecorder.cancel()
        if let keyboardSessionID {
            _ = try? preferences?.updateKeyboardDictationSession(
                id: keyboardSessionID,
                phase: .failed,
                errorMessage: "Voice dictation was canceled."
            )
        }
        self.keyboardDictationSessionID = nil
        dictationPhase = transcriptDraft.isEmpty ? .idle : .ready
        showNotice("Recording discarded", kind: .information)
    }

    func saveDraftForKeyboard() {
        let text = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showAlert(title: "Nothing to save", message: "Enter or dictate some text first.")
            return
        }

        do {
            try savePendingTranscript(text)
            dictationPhase = .ready
            showNotice("Ready in the BuddyGrammar keyboard", kind: .success)
        } catch {
            showAlert(title: "Couldn’t save transcript", message: error.localizedDescription)
        }
    }

    func clearTranscript() {
        preferences?.clearPendingTranscript()
        pendingTranscript = nil
        transcriptDraft = ""
        detectedLanguageCode = nil
        dictationPhase = .idle
        showNotice("Transcript cleared", kind: .information)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "buddygrammar" else { return }
        let destination = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if destination == "dictation" {
            selectedTab = .dictation
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let sessionID = components?.queryItems?
                .first(where: { $0.name == "session" })?
                .value
                .flatMap(UUID.init(uuidString:))
            if let sessionID,
               preferences?.loadKeyboardDictationSession()?.id == sessionID,
               !dictationPhase.isRecording,
               !dictationPhase.isProcessing {
                Task { [weak self] in
                    await self?.startDictation(keyboardSessionID: sessionID)
                }
            }
        }
    }

    func setQuickDictation(enabled: Bool) {
        guard enabled != settings.enablesQuickDictation else { return }
        if enabled, !DictationCompanionController.isSupported {
            showAlert(
                title: "Picture in Picture unavailable",
                message: "This device does not support Picture in Picture, so quick dictation cannot stay ready in the background."
            )
            return
        }
        settings.enablesQuickDictation = enabled
        persistSettings(successMessage: nil)
        companion.setEnabled(enabled)
        if enabled {
            showNotice(
                "Quick dictation is on. Leave the app and the companion window keeps the mic ready.",
                kind: .success
            )
        } else {
            showNotice("Quick dictation turned off", kind: .information)
        }
    }

    private func handleCompanionStartSignal() {
        appDictationLog.notice("Companion start signal received")
        guard settings.enablesQuickDictation else {
            appDictationLog.warning("Ignoring start signal: quick dictation disabled")
            return
        }
        guard !dictationPhase.isRecording, !dictationPhase.isProcessing else {
            appDictationLog.warning("Ignoring start signal: dictation already active")
            return
        }

        companionStartTask?.cancel()
        companionStartTask = Task { [weak self] in
            // The Darwin signal can outrun the keyboard's session write in
            // the shared container, so poll briefly for it to appear.
            for attempt in 0..<20 {
                guard let self, !Task.isCancelled else { return }
                if let session = preferences?.loadKeyboardDictationSession(),
                   session.phase == .launching {
                    guard settings.hasAcceptedCloudProcessing else {
                        appDictationLog.error("Start signal rejected: no cloud consent")
                        _ = try? preferences?.updateKeyboardDictationSession(
                            id: session.id,
                            phase: .failed,
                            errorMessage: "Allow cloud processing in the BuddyGrammar app first."
                        )
                        return
                    }
                    appDictationLog.notice("Starting companion dictation for session \(session.id, privacy: .public) after \(attempt, privacy: .public) retries")
                    await startDictation(keyboardSessionID: session.id)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            appDictationLog.error("Start signal timed out: no launching session found in shared container")
        }
    }

    private func handleCompanionStopSignal() {
        appDictationLog.notice("Companion stop signal received")
        guard dictationPhase.isRecording, keyboardDictationSessionID != nil else { return }
        Task { [weak self] in
            await self?.finishDictation()
        }
    }

    private func syncCompanionStatus() {
        switch dictationPhase {
        case .recording(let startedAt):
            companion.update(status: .recording(startedAt: startedAt))
        case .transcribing, .correcting:
            companion.update(status: .processing)
        case .idle, .ready:
            companion.update(status: .idle)
        }
    }

    private func monitorKeyboardStopRequest(sessionID: UUID) {
        keyboardStopMonitorTask?.cancel()
        keyboardStopMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                guard let session = preferences?.loadKeyboardDictationSession(),
                      session.id == sessionID else {
                    cancelRecording()
                    return
                }
                if session.phase == .stopRequested {
                    await finishDictation()
                    return
                }
            }
        }
    }

    private func beginBackgroundProcessing() {
        guard backgroundTaskIdentifier == .invalid else { return }
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
            withName: "BuddyGrammar keyboard transcription"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let sessionID = keyboardDictationSessionID {
                    _ = try? preferences?.updateKeyboardDictationSession(
                        id: sessionID,
                        phase: .failed,
                        errorMessage: "Voice dictation took too long to finish."
                    )
                }
                endBackgroundProcessing()
            }
        }
    }

    private func endBackgroundProcessing() {
        guard backgroundTaskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }

    private func savePendingTranscript(_ text: String) throws {
        guard let preferences else {
            throw SharedContainerError.unavailable
        }
        let transcript = PendingTranscript(text: text)
        try preferences.savePendingTranscript(transcript)
        pendingTranscript = transcript
    }

    private func persistSettings(successMessage: String?) {
        guard let preferences else {
            showAlert(
                title: "Couldn’t save preferences",
                message: SharedContainerError.unavailable.localizedDescription
            )
            return
        }

        do {
            try preferences.saveSettings(settings)
            if let successMessage {
                showNotice(successMessage, kind: .success)
            }
        } catch {
            showAlert(title: "Couldn’t save preferences", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    private func showNotice(_ message: String, kind: AppNotice.Kind) {
        let nextNotice = AppNotice(message: message, kind: kind)
        notice = nextNotice

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard self?.notice?.id == nextNotice.id else { return }
            self?.notice = nil
        }
    }

}

private enum SharedContainerError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "BuddyGrammar could not open its shared App Group, so the keyboard cannot receive this transcript."
    }
}
