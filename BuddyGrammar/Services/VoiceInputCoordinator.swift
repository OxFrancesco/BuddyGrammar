import Foundation
import Observation
import OSLog

private let voiceInputLogger = Logger(
    subsystem: "com.francescooddo.BuddyGrammar",
    category: "VoiceInput"
)

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

    private var isStarting = false
    private var activeConfiguration: VoiceSessionConfiguration?
    private var activeRoute: VoiceTranscriptionRoute?
    private var streamingSession: (any StreamingSpeechTranscriptionSession)?

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

        guard !isStarting else {
            voiceInputLogger.warning("Dictation start ignored because permission checks are already in progress.")
            return
        }

        isStarting = true
        startDictation()
    }

    private func startDictation() {
        Task { @MainActor in
            defer { isStarting = false }

            guard !isProcessing, !isRecording else {
                voiceInputLogger.warning("Dictation start rejected because another operation is active.")
                presentFailure(.busy)
                return
            }

            let configuration = makeSessionConfiguration()
            let localeIdentifier = configuration.localeIdentifier
            var pendingStreamingSession: (any StreamingSpeechTranscriptionSession)?

            do {
                var route = try await voiceModelStore.resolveRoute(for: localeIdentifier)
                voiceInputLogger.info("Dictation route resolved. locale=\(localeIdentifier, privacy: .public)")

                let microphoneGranted = await voiceAuthorizationService.requestMicrophoneAccess()
                guard microphoneGranted else {
                    throw RewriteFailure.microphonePermissionDenied
                }

                if case .apple(let requiresAuthorization) = route, requiresAuthorization {
                    let speechGranted = await voiceAuthorizationService.requestSpeechRecognitionAccess()
                    if !speechGranted, await voiceModelStore.fallbackModelIsPrepared() {
                        route = .whisper
                        voiceInputLogger.info("Using the prepared Whisper model because Speech Recognition permission was denied.")
                    } else if !speechGranted {
                        voiceInputLogger.error("Dictation speech recognition permission denied.")
                        throw RewriteFailure.speechRecognitionPermissionDenied
                    }
                }

                if case .apple = route {
                    pendingStreamingSession = await voiceModelStore.makeStreamingSession(
                        for: localeIdentifier
                    )
                }
                configurePCMStreaming(with: pendingStreamingSession)

                try audioRecordingService.startRecording()
                activeConfiguration = configuration
                activeRoute = route
                streamingSession = pendingStreamingSession
                isRecording = true
                lastErrorMessage = nil
                statusMessage = "Listening for your dictation..."
                menuBarStatus.show(.recording)
                voiceInputLogger.info(
                    "Dictation recording started. streaming=\(pendingStreamingSession != nil, privacy: .public)"
                )
            } catch let failure as RewriteFailure {
                pendingStreamingSession?.cancel()
                configurePCMStreaming(with: nil)
                voiceInputLogger.error("Dictation recording failed: \(failure.logMessage, privacy: .public)")
                presentFailure(failure)
            } catch {
                pendingStreamingSession?.cancel()
                configurePCMStreaming(with: nil)
                voiceInputLogger.error("Dictation recording failed: \(error.localizedDescription, privacy: .public)")
                presentFailure(.voiceRecordingFailed("BuddyWrite could not start recording audio. \(error.localizedDescription)"))
            }
        }
    }

    private func stopAndProcessDictation(accessibilityService: AccessibilityChecking) {
        Task { @MainActor in
            guard isRecording else { return }
            var stage = "stopping recording"
            let configuration = activeConfiguration ?? makeSessionConfiguration()
            let route = activeRoute
            let currentStreamingSession = streamingSession

            activeConfiguration = nil
            activeRoute = nil
            streamingSession = nil

            guard let audioURL = audioRecordingService.stopRecording() else {
                configurePCMStreaming(with: nil)
                currentStreamingSession?.cancel()
                isRecording = false
                voiceInputLogger.error("Dictation failed: recorder did not return an audio URL.")
                presentFailure(.voiceRecordingFailed("BuddyWrite could not access the recorded audio."))
                return
            }
            configurePCMStreaming(with: nil)

            isRecording = false
            isProcessing = true
            defer { isProcessing = false }
            defer { try? FileManager.default.removeItem(at: audioURL) }
            defer { currentStreamingSession?.cancel() }

            do {
                logRecordedAudio(at: audioURL)
                stage = "transcribing"
                statusMessage = "Transcribing your speech locally..."
                menuBarStatus.show(.transcribing)
                let transcript = try await voiceModelStore.transcribe(
                    audioURL: audioURL,
                    localeIdentifier: configuration.localeIdentifier,
                    route: route,
                    streamingSession: currentStreamingSession
                )
                voiceInputLogger.info("Dictation transcription succeeded. transcriptCharacters=\(transcript.count, privacy: .public)")

                let profile = configuration.profile
                stage = "rewriting"
                statusMessage = "Rewriting your dictated text with \(profile.name)..."
                menuBarStatus.show(.sending(profileName: profile.name))
                let output: String
                let usedRawTranscript: Bool
                do {
                    let result = try await rewriteProvider.rewrite(
                        RewriteRequest(profile: profile, selectedText: transcript)
                    )
                    output = result.rewrittenText
                    usedRawTranscript = false
                    voiceInputLogger.info("Dictation rewrite succeeded. outputCharacters=\(output.count, privacy: .public)")
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    output = transcript
                    usedRawTranscript = true
                    voiceInputLogger.error(
                        "Dictation rewrite failed; delivering the raw local transcript. error=\(error.localizedDescription, privacy: .public)"
                    )
                }

                switch configuration.outputMode {
                case .replaceSelection:
                    stage = "checking accessibility permission"
                    guard accessibilityService.isTrusted(prompt: true) else {
                        throw RewriteFailure.accessibilityPermissionDenied
                    }
                    stage = "pasting"
                    try await pasteReplacement(output)
                    statusMessage = usedRawTranscript
                        ? "Inserted the raw dictation because rewriting was unavailable."
                        : "Inserted \(profile.name.lowercased()) output."
                    menuBarStatus.show(
                        .success(message: usedRawTranscript ? "Raw dictation inserted" : "Dictation inserted")
                    )
                    voiceInputLogger.info("Dictation paste succeeded.")
                case .copyToClipboard:
                    stage = "copying to clipboard"
                    clipboardService.writeString(output)
                    statusMessage = usedRawTranscript
                        ? "Copied the raw dictation because rewriting was unavailable."
                        : "Copied dictated \(profile.name.lowercased()) output to the clipboard."
                    menuBarStatus.show(
                        .success(message: usedRawTranscript ? "Raw dictation copied" : "Dictation copied")
                    )
                    voiceInputLogger.info("Dictation copy-to-clipboard succeeded.")
                }

                lastErrorMessage = nil
                menuBarStatus.reset(after: .seconds(1.6))
            } catch let failure as RewriteFailure {
                voiceInputLogger.error("Dictation failed while \(stage, privacy: .public): \(failure.logMessage, privacy: .public)")
                presentFailure(failure)
            } catch {
                voiceInputLogger.error("Dictation failed while \(stage, privacy: .public): \(error.localizedDescription, privacy: .public)")
                presentFailure(.transcriptionUnavailable("BuddyWrite failed while \(stage): \(error.localizedDescription)"))
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

    private func makeSessionConfiguration() -> VoiceSessionConfiguration {
        VoiceSessionConfiguration(
            localeIdentifier: settingsProvider.appSettings.voiceLocaleIdentifier
                ?? Locale.autoupdatingCurrent.identifier,
            profile: resolveVoiceProfile(),
            outputMode: settingsProvider.appSettings.outputMode
        )
    }

    private func configurePCMStreaming(
        with session: (any StreamingSpeechTranscriptionSession)?
    ) {
        guard let recorder = audioRecordingService as? any PCMStreamingAudioRecording else { return }
        guard let session else {
            recorder.setPCM16SampleHandler(nil)
            return
        }

        recorder.setPCM16SampleHandler { [session] data in
            session.appendPCM16(data)
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

    private func logRecordedAudio(at url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        voiceInputLogger.info("Dictation recording stopped. bytes=\(bytes, privacy: .public)")
    }
}

private struct VoiceSessionConfiguration {
    let localeIdentifier: String
    let profile: PromptProfile
    let outputMode: OutputMode
}

private extension RewriteFailure {
    var logMessage: String {
        errorDescription ?? String(describing: self)
    }
}
