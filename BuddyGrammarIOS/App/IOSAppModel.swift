import BuddyGrammarKit
import Foundation
import Observation

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
    var dictationPhase: DictationPhase = .idle
    var selectedTab: AppTab = .home
    var detectedLanguageCode: String?
    var alert: AppAlert?
    var notice: AppNotice?
    let isSharedContainerReady: Bool

    private let preferences: SharedPreferences?
    private let audioRecorder: IOSAudioRecorder
    private let transcriptionClient: ElevenLabsTranscriptionClient
    private let correctionClient: OpenRouterCorrectionClient

    init(
        preferences: SharedPreferences? = nil,
        audioRecorder: IOSAudioRecorder = IOSAudioRecorder(),
        transcriptionClient: ElevenLabsTranscriptionClient = ElevenLabsTranscriptionClient(),
        correctionClient: OpenRouterCorrectionClient = OpenRouterCorrectionClient()
    ) {
        let sharedPreferences = preferences ?? SharedPreferences()
        isSharedContainerReady = sharedPreferences != nil
        self.preferences = sharedPreferences
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
    }

    var isCloudReady: Bool {
        isSharedContainerReady
            && settings.hasAcceptedCloudProcessing
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
        correctionInstruction: String,
        autoCorrectDictation: Bool,
        acceptsCloudProcessing: Bool
    ) {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = correctionInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedModelID.isEmpty, !trimmedInstruction.isEmpty else {
            showAlert(
                title: "Check correction settings",
                message: "The OpenRouter model and correction instructions cannot be empty."
            )
            return
        }

        settings.openRouterModelID = trimmedModelID
        settings.correctionInstruction = trimmedInstruction
        settings.autoCorrectDictation = autoCorrectDictation
        settings.hasAcceptedCloudProcessing = acceptsCloudProcessing
        persistSettings(successMessage: "Preferences saved")
    }

    func startDictation() async {
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
        } catch {
            dictationPhase = .idle
            showAlert(title: "Couldn’t start recording", message: error.localizedDescription)
        }
    }

    func finishDictation() async {
        guard dictationPhase.isRecording else { return }

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
                        modelID: settings.openRouterModelID,
                        instruction: settings.correctionInstruction
                    )
                } catch {
                    correctionFailure = error
                }
            }

            transcriptDraft = finalText
            try savePendingTranscript(finalText)
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
            dictationPhase = transcriptDraft.isEmpty ? .idle : .ready
            showAlert(title: "Dictation failed", message: error.localizedDescription)
        }
    }

    func cancelRecording() {
        audioRecorder.cancel()
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

    func handleAppLeavingForeground() {
        guard dictationPhase.isRecording else { return }
        audioRecorder.cancel()
        dictationPhase = transcriptDraft.isEmpty ? .idle : .ready
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
