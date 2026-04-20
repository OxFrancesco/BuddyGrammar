import Foundation
import Observation

@MainActor
protocol VoiceSettingsProviding: AnyObject {
    var appSettings: AppSettings { get }
    func profile(id: UUID) -> PromptProfile?
}

@MainActor
protocol TextRewriting: AnyObject {
    func rewrite(_ request: RewriteRequest) async throws -> RewriteResult
}

protocol ClipboardWriting: AnyObject {
    func snapshot() -> ClipboardSnapshot
    func writeString(_ string: String)
    func restore(_ snapshot: ClipboardSnapshot)
}

@MainActor
protocol PasteSimulating: AnyObject {
    func simulatePaste() throws
}

@MainActor
protocol AccessibilityChecking: AnyObject {
    func isTrusted(prompt: Bool) -> Bool
}

extension SettingsStore: VoiceSettingsProviding {}
extension RewriteProviderController: TextRewriting {}
extension ClipboardService: ClipboardWriting {}
extension EventSimulationService: PasteSimulating {}
extension AccessibilityService: AccessibilityChecking {}

@MainActor
@Observable
final class VoiceInputCoordinator {
    var statusMessage = "Ready"
    var lastErrorMessage: String?
    var isProcessing = false
    var isRecording = false

    private let settingsProvider: VoiceSettingsProviding
    private let rewriteProvider: TextRewriting
    private let clipboardService: ClipboardWriting
    private let eventSimulationService: PasteSimulating
    private let voiceAuthorizationService: VoiceAuthorizing
    private let audioRecordingService: AudioRecording
    private let voiceModelStore: VoiceModelStore
    private let menuBarStatus: MenuBarStatusModel

    init(
        settingsProvider: VoiceSettingsProviding,
        rewriteProvider: TextRewriting,
        clipboardService: ClipboardWriting,
        eventSimulationService: PasteSimulating,
        voiceAuthorizationService: VoiceAuthorizing,
        audioRecordingService: AudioRecording,
        voiceModelStore: VoiceModelStore,
        menuBarStatus: MenuBarStatusModel
    ) {
        self.settingsProvider = settingsProvider
        self.rewriteProvider = rewriteProvider
        self.clipboardService = clipboardService
        self.eventSimulationService = eventSimulationService
        self.voiceAuthorizationService = voiceAuthorizationService
        self.audioRecordingService = audioRecordingService
        self.voiceModelStore = voiceModelStore
        self.menuBarStatus = menuBarStatus
    }

    func toggleDictation(accessibilityService: AccessibilityChecking) {
        if isRecording {
            stopAndProcessDictation(accessibilityService: accessibilityService)
            return
        }

        guard !isProcessing else {
            presentFailure(.busy)
            return
        }

        startDictation()
    }

    private func startDictation() {
        Task { @MainActor in
            guard !isProcessing, !isRecording else {
                presentFailure(.busy)
                return
            }

            let microphoneGranted = await voiceAuthorizationService.requestMicrophoneAccess()
            guard microphoneGranted else {
                presentFailure(.microphonePermissionDenied)
                return
            }

            let speechGranted = await voiceAuthorizationService.requestSpeechRecognitionAccess()
            guard speechGranted else {
                presentFailure(.speechRecognitionPermissionDenied)
                return
            }

            do {
                try audioRecordingService.startRecording()
                isRecording = true
                lastErrorMessage = nil
                statusMessage = "Listening for your dictation..."
                menuBarStatus.show(.recording)
            } catch let failure as RewriteFailure {
                presentFailure(failure)
            } catch {
                presentFailure(.voiceRecordingFailed("BuddyWrite could not start recording audio. \(error.localizedDescription)"))
            }
        }
    }

    private func stopAndProcessDictation(accessibilityService: AccessibilityChecking) {
        Task { @MainActor in
            guard isRecording else { return }
            guard let audioURL = audioRecordingService.stopRecording() else {
                isRecording = false
                presentFailure(.voiceRecordingFailed("BuddyWrite could not access the recorded audio."))
                return
            }

            isRecording = false
            isProcessing = true
            defer { isProcessing = false }
            defer { try? FileManager.default.removeItem(at: audioURL) }

            do {
                let voiceLocaleIdentifier = settingsProvider.appSettings.voiceLocaleIdentifier ?? Locale.autoupdatingCurrent.identifier
                statusMessage = "Transcribing your speech locally..."
                menuBarStatus.show(.transcribing)
                let transcript = try await voiceModelStore.transcribe(audioURL: audioURL, localeIdentifier: voiceLocaleIdentifier)

                let profile = resolveVoiceProfile()
                statusMessage = "Rewriting your dictated text with \(profile.name)..."
                menuBarStatus.show(.sending(profileName: profile.name))
                let result = try await rewriteProvider.rewrite(
                    RewriteRequest(profile: profile, selectedText: transcript)
                )

                switch settingsProvider.appSettings.outputMode {
                case .replaceSelection:
                    guard accessibilityService.isTrusted(prompt: true) else {
                        throw RewriteFailure.accessibilityPermissionDenied
                    }
                    try await pasteReplacement(result.rewrittenText)
                    statusMessage = "Inserted \(profile.name.lowercased()) output."
                    menuBarStatus.show(.success(message: "Dictation inserted"))
                case .copyToClipboard:
                    clipboardService.writeString(result.rewrittenText)
                    statusMessage = "Copied dictated \(profile.name.lowercased()) output to the clipboard."
                    menuBarStatus.show(.success(message: "Dictation copied"))
                }

                lastErrorMessage = nil
                menuBarStatus.reset(after: .seconds(1.6))
            } catch let failure as RewriteFailure {
                presentFailure(failure)
            } catch {
                presentFailure(.transcriptionUnavailable(error.localizedDescription))
            }
        }
    }

    private func resolveVoiceProfile() -> PromptProfile {
        if let voiceProfileID = settingsProvider.appSettings.voiceProfileID,
           let voiceProfile = settingsProvider.profile(id: voiceProfileID) {
            return voiceProfile
        }

        return settingsProvider.profile(id: PromptProfile.grammarProfileID) ?? PromptProfile.standard
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
