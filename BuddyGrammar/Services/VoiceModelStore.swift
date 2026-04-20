import Foundation
import Observation
import Speech
import WhisperKit

extension WhisperKit: @retroactive @unchecked Sendable {}

@MainActor
protocol SpeechTranscriptionEngine: AnyObject {
    func isAvailable(for localeIdentifier: String) async -> Bool
    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String
}

@MainActor
protocol FallbackSpeechTranscriptionEngine: SpeechTranscriptionEngine {
    func preload() async throws
    func isPrepared() async -> Bool
}

enum VoiceFallbackModelID: String, CaseIterable, Codable, Identifiable, Sendable {
    case whisperBase

    var id: Self { self }

    var title: String {
        switch self {
        case .whisperBase:
            "Whisper Base"
        }
    }

    var badge: String {
        "~146 MB"
    }

    var summary: String {
        "Small multilingual fallback model for Macs without Apple on-device speech support."
    }

    var whisperKitModelName: String {
        "base"
    }
}

enum VoiceModelState: String, Codable, Hashable, Sendable {
    case notDownloaded
    case downloading
    case loaded
    case failed

    var title: String {
        switch self {
        case .notDownloaded:
            "Not downloaded"
        case .downloading:
            "Downloading"
        case .loaded:
            "Loaded"
        case .failed:
            "Failed"
        }
    }
}

struct VoiceModelStatus: Hashable, Sendable {
    var state: VoiceModelState
    var errorMessage: String?

    static let notDownloaded = VoiceModelStatus(state: .notDownloaded, errorMessage: nil)
}

@MainActor
final class AppleOnDeviceSpeechEngine: SpeechTranscriptionEngine {
    private var activeTask: SFSpeechRecognitionTask?

    func isAvailable(for localeIdentifier: String) async -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: bestLocale(for: localeIdentifier)) else {
            return false
        }
        return recognizer.supportsOnDeviceRecognition
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        let locale = bestLocale(for: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw RewriteFailure.transcriptionUnavailable("BuddyWrite could not create a speech recognizer for \(locale.identifier).")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw RewriteFailure.transcriptionUnavailable(
                "Apple on-device speech is unavailable for \(locale.identifier) on this Mac."
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            activeTask?.cancel()
            activeTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard !hasResumed else { return }

                if let error {
                    hasResumed = true
                    self?.activeTask = nil
                    continuation.resume(
                        throwing: RewriteFailure.transcriptionUnavailable(
                            "BuddyWrite could not transcribe the recorded audio locally. \(error.localizedDescription)"
                        )
                    )
                    return
                }

                guard let result, result.isFinal else { return }
                hasResumed = true
                self?.activeTask = nil
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    continuation.resume(
                        throwing: RewriteFailure.transcriptionUnavailable("BuddyWrite could not hear any speech in the recording.")
                    )
                } else {
                    continuation.resume(returning: text)
                }
            }
        }
    }

    private func bestLocale(for localeIdentifier: String) -> Locale {
        let normalizedIdentifier = Self.normalized(localeIdentifier)
        let supportedLocales = SFSpeechRecognizer.supportedLocales()

        if let exactMatch = supportedLocales.first(where: { Self.normalized($0.identifier) == normalizedIdentifier }) {
            return exactMatch
        }

        let languageCode = normalizedIdentifier.split(separator: "-").first.map(String.init) ?? normalizedIdentifier
        if let languageMatch = supportedLocales.first(where: {
            Self.normalized($0.identifier).split(separator: "-").first.map(String.init) == languageCode
        }) {
            return languageMatch
        }

        return Locale(identifier: localeIdentifier)
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

@MainActor
final class WhisperKitSpeechEngine: FallbackSpeechTranscriptionEngine {
    private let modelID: VoiceFallbackModelID
    private var whisperKit: WhisperKit?

    init(modelID: VoiceFallbackModelID = .whisperBase) {
        self.modelID = modelID
    }

    func isAvailable(for localeIdentifier: String) async -> Bool {
        true
    }

    func isPrepared() async -> Bool {
        whisperKit != nil
    }

    func preload() async throws {
        if whisperKit != nil {
            return
        }

        whisperKit = try await WhisperKit(
            WhisperKitConfig(
                model: modelID.whisperKitModelName,
                verbose: false,
                prewarm: false,
                load: true,
                download: true
            )
        )
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        guard let whisperKit else {
            throw RewriteFailure.transcriptionUnavailable(
                "Download the local Whisper fallback model in Settings before using dictation on this Mac."
            )
        }

        let results = try await whisperKit.transcribe(audioPath: audioURL.path)
        guard let result = results.first else {
            throw RewriteFailure.transcriptionUnavailable("BuddyWrite could not transcribe the recorded audio with Whisper.")
        }

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw RewriteFailure.transcriptionUnavailable("BuddyWrite could not hear any speech in the recording.")
        }
        return text
    }
}

@MainActor
@Observable
final class VoiceModelStore {
    let fallbackModelID: VoiceFallbackModelID

    private let appleEngine: any SpeechTranscriptionEngine
    private let fallbackEngine: any FallbackSpeechTranscriptionEngine

    var status: VoiceModelStatus
    var lastErrorMessage: String?

    init(
        fallbackModelID: VoiceFallbackModelID = .whisperBase,
        appleEngine: any SpeechTranscriptionEngine = AppleOnDeviceSpeechEngine(),
        fallbackEngine: any FallbackSpeechTranscriptionEngine = WhisperKitSpeechEngine()
    ) {
        self.fallbackModelID = fallbackModelID
        self.appleEngine = appleEngine
        self.fallbackEngine = fallbackEngine
        self.status = .notDownloaded
    }

    func appleOnDeviceAvailable(for localeIdentifier: String) async -> Bool {
        await appleEngine.isAvailable(for: localeIdentifier)
    }

    func preloadFallbackModel() {
        guard status.state != .downloading else { return }

        status = .init(state: .downloading, errorMessage: nil)
        lastErrorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.fallbackEngine.preload()
                await MainActor.run {
                    self.status = .init(state: .loaded, errorMessage: nil)
                    self.lastErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    let message = "BuddyWrite could not download the Whisper fallback model. \(error.localizedDescription)"
                    self.status = .init(state: .failed, errorMessage: message)
                    self.lastErrorMessage = message
                }
            }
        }
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        if await appleEngine.isAvailable(for: localeIdentifier) {
            lastErrorMessage = nil
            return try await appleEngine.transcribe(audioURL: audioURL, localeIdentifier: localeIdentifier)
        }

        let fallbackPrepared = await fallbackEngine.isPrepared()
        if !fallbackPrepared {
            let message = "Apple on-device speech is unavailable for this language on this Mac. Download the Whisper fallback model in Settings to keep dictation fully local."
            lastErrorMessage = message
            if status.state == .notDownloaded {
                status = .init(state: .notDownloaded, errorMessage: message)
            }
            throw RewriteFailure.transcriptionUnavailable(message)
        }

        status = .init(state: .loaded, errorMessage: nil)
        lastErrorMessage = nil

        do {
            return try await fallbackEngine.transcribe(audioURL: audioURL, localeIdentifier: localeIdentifier)
        } catch let failure as RewriteFailure {
            let message = failure.errorDescription ?? "BuddyWrite could not transcribe the recorded audio."
            recordFailure(message)
            throw failure
        } catch {
            let message = "BuddyWrite could not transcribe the recorded audio. \(error.localizedDescription)"
            recordFailure(message)
            throw RewriteFailure.transcriptionUnavailable(message)
        }
    }

    private func recordFailure(_ message: String) {
        status = .init(state: .failed, errorMessage: message)
        lastErrorMessage = message
    }
}
