import BuddyGrammarKit
import Foundation
import Observation
import UIKit

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
    private let adaptiveStore: AdaptiveLearningStore?
    private let audioRecorder: IOSAudioRecorder
    private let transcriptionClient: ElevenLabsTranscriptionClient
    private let textPolisher: DictationTextPolisher
    private let dynamicIslandController: DynamicIslandDictationController

    init(
        preferences: SharedPreferences? = nil,
        adaptiveStore: AdaptiveLearningStore? = nil,
        audioRecorder: IOSAudioRecorder = IOSAudioRecorder(),
        transcriptionClient: ElevenLabsTranscriptionClient = ElevenLabsTranscriptionClient(),
        correctionClient: OpenRouterCorrectionClient = OpenRouterCorrectionClient()
    ) {
        let sharedPreferences = preferences ?? SharedPreferences()
        isSharedContainerReady = sharedPreferences != nil
        self.preferences = sharedPreferences
        self.adaptiveStore = adaptiveStore ?? AdaptiveLearningStore()
        self.audioRecorder = audioRecorder
        self.transcriptionClient = transcriptionClient
        self.textPolisher = DictationTextPolisher(cloudClient: correctionClient)
        self.dynamicIslandController = DynamicIslandDictationController(
            preferences: sharedPreferences
        )

        var loadedSettings = sharedPreferences?.loadSettings() ?? .default
        var loadedTranscript = sharedPreferences?.loadPendingTranscript()
        var loadedDictation = sharedPreferences?.loadSavedDictation()

        // Keyboard-triggered microphone readiness relied on keeping the
        // containing app alive, which is not a supported custom-keyboard
        // contract. Migrate existing installs to the honest app-started flow.
        if loadedSettings.enablesQuickDictation {
            loadedSettings.enablesQuickDictation = false
            loadedSettings.quickDictationExpiresAt = nil
            try? sharedPreferences?.saveSettings(loadedSettings)
        }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--reset-onboarding") {
            loadedSettings = .default
            loadedTranscript = nil
            loadedDictation = nil
            try? sharedPreferences?.saveSettings(loadedSettings)
            sharedPreferences?.clearPendingTranscript()
            sharedPreferences?.clearSavedDictation()
        }

        if arguments.contains("--ui-testing") || arguments.contains("--uitesting") {
            loadedSettings.hasCompletedOnboarding = true
            loadedSettings.hasAcceptedCloudProcessing = true
            loadedSettings.enablesQuickDictation = false
            loadedSettings.quickDictationExpiresAt = nil
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
        transcriptDraft = loadedTranscript?.text ?? loadedDictation?.text ?? ""
        detectedLanguageCode = loadedTranscript?.languageCode ?? loadedDictation?.languageCode

        if !isSharedContainerReady {
            alert = AppAlert(
                title: "Keyboard sharing unavailable",
                message: "BuddyGrammar could not open its shared App Group. Reinstall the signed app before saving a transcript for the keyboard."
            )
        }

        Task { [dynamicIslandController] in
            await dynamicIslandController.deactivate()
        }

    }

    var isCloudReady: Bool {
        isSharedContainerReady
            && settings.hasAcceptedCloudProcessing
    }

    func refresh() {
        if let preferences {
            settings = preferences.loadSettings()
            if settings.enablesQuickDictation {
                settings.enablesQuickDictation = false
                settings.quickDictationExpiresAt = nil
                try? preferences.saveSettings(settings)
            }
            pendingTranscript = preferences.loadPendingTranscript()
            if transcriptDraft.isEmpty {
                let savedDictation = preferences.loadSavedDictation()
                transcriptDraft = pendingTranscript?.text ?? savedDictation?.text ?? ""
                detectedLanguageCode = pendingTranscript?.languageCode
                    ?? savedDictation?.languageCode
            }
        }
        Task { [dynamicIslandController] in
            await dynamicIslandController.deactivate()
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
        adaptiveTypingEnabled: Bool,
        personalizedPracticeEnabled: Bool,
        acceptsCloudProcessing: Bool,
        copiesCompletedDictationToClipboard: Bool
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
        settings.adaptiveTypingEnabled = adaptiveTypingEnabled
        settings.personalizedPracticeEnabled = personalizedPracticeEnabled
        settings.hasAcceptedCloudProcessing = acceptsCloudProcessing
        settings.enablesQuickDictation = false
        settings.quickDictationExpiresAt = nil
        settings.copiesCompletedDictationToClipboard = copiesCompletedDictationToClipboard
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

        // A recording begins only while the containing app is visibly active.
        await dynamicIslandController.deactivate()

        do {
            let startedAt = try await audioRecorder.start()
            dictationPhase = .recording(startedAt: startedAt)
            if settings.autoCorrectDictation {
                let canUseOnDevice = UIApplication.shared.applicationState == .active
                Task { [textPolisher] in
                    await textPolisher.warmUp(canUseOnDevice: canUseOnDevice)
                }
            }
            detectedLanguageCode = nil
        } catch {
            dictationPhase = .idle
            showAlert(title: "Couldn’t start recording", message: error.localizedDescription)
            await dynamicIslandController.deactivate()
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
            let languageHint = Locale.preferredLanguages.first?
                .split(separator: "-")
                .first
                .map(String.init)
            let transcript = try await transcriptionClient.transcribe(
                audioData: audioData,
                clientID: clientID,
                languageCode: languageHint
            )

            detectedLanguageCode = transcript.languageCode
            var finalText = transcript.text
            var correctionFailure: Error?

            if settings.autoCorrectDictation {
                dictationPhase = .correcting
                do {
                    finalText = try await textPolisher.polish(
                        text: finalText,
                        clientID: clientID,
                        modelID: settings.activeOpenRouterModelID,
                        instruction: settings.correctionInstruction,
                        languageCode: transcript.languageCode,
                        canUseOnDevice: UIApplication.shared.applicationState == .active
                    )
                } catch {
                    correctionFailure = error
                }
            }

            transcriptDraft = finalText
            try saveCompletedDictation(
                rawTranscript: transcript.text,
                text: finalText,
                languageCode: transcript.languageCode
            )
            let copiedToClipboard = settings.copiesCompletedDictationToClipboard
            if copiedToClipboard {
                copyToClipboard(finalText)
            }
            dictationPhase = .ready

            if let correctionFailure {
                let savedResult = copiedToClipboard
                    ? "Transcript saved and copied"
                    : "Transcript saved locally"
                showNotice(
                    "\(savedResult) without correction: \(correctionFailure.localizedDescription)",
                    kind: .information
                )
            } else {
                showNotice(
                    copiedToClipboard
                        ? "Saved locally, copied, and ready for the keyboard"
                        : "Saved locally and ready for the keyboard",
                    kind: .success
                )
            }
        } catch {
            dictationPhase = transcriptDraft.isEmpty ? .idle : .ready
            showAlert(title: "Dictation failed", message: error.localizedDescription)
        }
        await dynamicIslandController.deactivate()
    }

    func cancelRecording() {
        audioRecorder.cancel()
        dictationPhase = transcriptDraft.isEmpty ? .idle : .ready
        showNotice("Recording discarded", kind: .information)
        Task { [weak self] in
            guard let self else { return }
            await dynamicIslandController.deactivate()
        }
    }

    func saveDraftForKeyboard() {
        let text = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showAlert(title: "Nothing to save", message: "Enter or dictate some text first.")
            return
        }

        do {
            try savePendingTranscript(
                text,
                languageCode: detectedLanguageCode
            )
            try preferences?.saveDictation(
                SavedDictation(
                    rawTranscript: text,
                    text: text,
                    languageCode: detectedLanguageCode
                )
            )
            let copiedToClipboard = settings.copiesCompletedDictationToClipboard
            if copiedToClipboard {
                copyToClipboard(text)
            }
            dictationPhase = .ready
            showNotice(
                copiedToClipboard
                    ? "Saved locally, copied, and ready for the keyboard"
                    : "Saved locally and ready for the keyboard",
                kind: .success
            )
        } catch {
            showAlert(title: "Couldn’t save transcript", message: error.localizedDescription)
        }
    }

    func clearTranscript() {
        preferences?.clearPendingTranscript()
        preferences?.clearSavedDictation()
        pendingTranscript = nil
        transcriptDraft = ""
        detectedLanguageCode = nil
        dictationPhase = .idle
        showNotice("Transcript cleared", kind: .information)
    }

    func resetAdaptiveLearning(_ scope: AdaptiveLearningScope) {
        guard let adaptiveStore, let preferences else {
            showAlert(
                title: "Couldn’t reset learning",
                message: SharedContainerError.unavailable.localizedDescription
            )
            return
        }
        adaptiveStore.reset(scope)
        if scope == .language || scope == .all {
            preferences.resetPersonalLanguageLearning()
        }
        showNotice(resetMessage(for: scope), kind: .information)
    }

    private func resetMessage(for scope: AdaptiveLearningScope) -> String {
        switch scope {
        case .typing: "Touch calibration reset"
        case .language: "Learned words reset"
        case .practice: "Practice history reset"
        case .all: "All on-device learning reset"
        }
    }

    private func savePendingTranscript(
        _ text: String,
        languageCode: String?
    ) throws {
        guard let preferences else {
            throw SharedContainerError.unavailable
        }
        let transcript = PendingTranscript(
            text: text,
            languageCode: languageCode
        )
        try preferences.savePendingTranscript(transcript)
        pendingTranscript = transcript
    }

    private func saveCompletedDictation(
        rawTranscript: String,
        text: String,
        languageCode: String?
    ) throws {
        guard let preferences else {
            throw SharedContainerError.unavailable
        }
        try preferences.saveDictation(
            SavedDictation(
                rawTranscript: rawTranscript,
                text: text,
                languageCode: languageCode
            )
        )
        try savePendingTranscript(text, languageCode: languageCode)
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
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
