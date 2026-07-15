@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech
import WhisperKit

extension WhisperKit: @retroactive @unchecked Sendable {}

@MainActor
protocol SpeechTranscriptionEngine: AnyObject {
    func isAvailable(for localeIdentifier: String) async -> Bool
    func requiresSpeechRecognitionAuthorization(for localeIdentifier: String) async -> Bool
    func makeStreamingSession(localeIdentifier: String) async -> (any StreamingSpeechTranscriptionSession)?
    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String
}

protocol StreamingSpeechTranscriptionSession: AnyObject, Sendable {
    func appendPCM16(_ data: Data)
    func finish() async throws -> String
    func cancel()
}

extension SpeechTranscriptionEngine {
    func requiresSpeechRecognitionAuthorization(for localeIdentifier: String) async -> Bool {
        true
    }

    func makeStreamingSession(localeIdentifier: String) async -> (any StreamingSpeechTranscriptionSession)? {
        nil
    }
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

enum VoiceTranscriptionRoute: Equatable, Sendable {
    case apple(requiresSpeechRecognitionAuthorization: Bool)
    case whisper
}

@MainActor
final class AppleOnDeviceSpeechEngine: SpeechTranscriptionEngine {
    private let legacyEngine = LegacySFSpeechRecognitionEngine()

    func isAvailable(for localeIdentifier: String) async -> Bool {
        if #available(macOS 26.0, *) {
            let modernEngine = AppleSpeechAnalyzerEngine()
            if await modernEngine.isAvailable(for: localeIdentifier) {
                return true
            }
        }
        return await legacyEngine.isAvailable(for: localeIdentifier)
    }

    func requiresSpeechRecognitionAuthorization(for localeIdentifier: String) async -> Bool {
        if #available(macOS 26.0, *) {
            let modernEngine = AppleSpeechAnalyzerEngine()
            if await modernEngine.isAvailable(for: localeIdentifier) {
                return false
            }
        }
        return true
    }

    func makeStreamingSession(localeIdentifier: String) async -> (any StreamingSpeechTranscriptionSession)? {
        guard #available(macOS 26.0, *) else { return nil }

        let modernEngine = AppleSpeechAnalyzerEngine()
        guard await modernEngine.isAvailable(for: localeIdentifier) else { return nil }
        return await modernEngine.makeStreamingSession(localeIdentifier: localeIdentifier)
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        if #available(macOS 26.0, *) {
            let modernEngine = AppleSpeechAnalyzerEngine()
            if await modernEngine.isAvailable(for: localeIdentifier) {
                do {
                    return try await modernEngine.transcribe(
                        audioURL: audioURL,
                        localeIdentifier: localeIdentifier
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if legacyEngine.authorizationIsGranted,
                       await legacyEngine.isAvailable(for: localeIdentifier) {
                        return try await legacyEngine.transcribe(
                            audioURL: audioURL,
                            localeIdentifier: localeIdentifier
                        )
                    }
                    throw error
                }
            }
        }

        return try await legacyEngine.transcribe(
            audioURL: audioURL,
            localeIdentifier: localeIdentifier
        )
    }
}

@MainActor
private final class LegacySFSpeechRecognitionEngine: SpeechTranscriptionEngine {
    private var activeTask: SFSpeechRecognitionTask?
    private var activeGate: LegacyRecognitionContinuationGate?
    private var activeRecognitionID: UUID?
    private var timeoutTask: Task<Void, Never>?

    var authorizationIsGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func isAvailable(for localeIdentifier: String) async -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: bestLocale(for: localeIdentifier)) else {
            return false
        }
        return recognizer.supportsOnDeviceRecognition
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        try Task.checkCancellation()
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

        cancelActiveRecognition(throwing: CancellationError())
        let recognitionID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = LegacyRecognitionContinuationGate(continuation: continuation)
                activeRecognitionID = recognitionID
                activeGate = gate
                activeTask = recognizer.recognitionTask(with: request) { result, error in
                    let didResolve: Bool
                    if let error {
                        didResolve = gate.resume(
                            throwing: RewriteFailure.transcriptionUnavailable(
                                "BuddyWrite could not transcribe the recorded audio locally. \(error.localizedDescription)"
                            )
                        )
                    } else if let result, result.isFinal {
                        let text = result.bestTranscription.formattedString
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if text.isEmpty {
                            didResolve = gate.resume(
                                throwing: RewriteFailure.transcriptionUnavailable(
                                    "BuddyWrite could not hear any speech in the recording."
                                )
                            )
                        } else {
                            didResolve = gate.resume(returning: text)
                        }
                    } else {
                        didResolve = false
                    }

                    if didResolve {
                        Task { @MainActor [weak self] in
                            self?.clearActiveRecognition(matching: recognitionID, cancelTask: false)
                        }
                    }
                }

                timeoutTask = Task { @MainActor [weak self, gate] in
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return
                    }

                    let didResolve = gate.resume(
                        throwing: RewriteFailure.transcriptionUnavailable(
                            "Apple Speech Recognition did not finish in time."
                        )
                    )
                    if didResolve {
                        self?.clearActiveRecognition(matching: recognitionID, cancelTask: true)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelActiveRecognition(
                    matching: recognitionID,
                    throwing: CancellationError()
                )
            }
        }
    }

    private func cancelActiveRecognition(
        matching recognitionID: UUID? = nil,
        throwing error: any Error
    ) {
        if let recognitionID, activeRecognitionID != recognitionID {
            return
        }

        let gate = activeGate
        gate?.resume(throwing: error)
        clearActiveRecognition(matching: activeRecognitionID, cancelTask: true)
    }

    private func clearActiveRecognition(matching recognitionID: UUID?, cancelTask: Bool) {
        guard activeRecognitionID == recognitionID else { return }
        if cancelTask {
            activeTask?.cancel()
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        activeTask = nil
        activeGate = nil
        activeRecognitionID = nil
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

private final class LegacyRecognitionContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, any Error>?

    init(continuation: CheckedContinuation<String, any Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(returning value: String) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func resume(throwing error: any Error) -> Bool {
        guard let continuation = takeContinuation() else { return false }
        continuation.resume(throwing: error)
        return true
    }

    private func takeContinuation() -> CheckedContinuation<String, any Error>? {
        lock.lock()
        defer { lock.unlock() }

        guard let continuation else { return nil }
        self.continuation = nil
        return continuation
    }
}

@available(macOS 26.0, *)
@MainActor
private final class AppleSpeechAnalyzerEngine: SpeechTranscriptionEngine {
    func isAvailable(for localeIdentifier: String) async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechAnalyzerSupport.resolveLocale(for: localeIdentifier) != nil
    }

    func requiresSpeechRecognitionAuthorization(for localeIdentifier: String) async -> Bool {
        false
    }

    func makeStreamingSession(localeIdentifier: String) async -> (any StreamingSpeechTranscriptionSession)? {
        let session = SpeechAnalyzerStreamingSession(localeIdentifier: localeIdentifier)
        session.start()
        return session
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechAnalyzerFailure.unavailable
        }
        guard let locale = await SpeechAnalyzerSupport.resolveLocale(for: localeIdentifier) else {
            throw SpeechAnalyzerFailure.unsupportedLocale(localeIdentifier)
        }

        let transcriber = SpeechAnalyzerSupport.makeTranscriber(locale: locale)
        try await SpeechAnalyzerSupport.ensureAssets(for: transcriber, locale: locale)
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        let audioFile = try AVAudioFile(forReading: audioURL)
        let audioDuration = Double(audioFile.length) / max(audioFile.processingFormat.sampleRate, 1)
        let resultsTask = SpeechAnalyzerSupport.collectResults(from: transcriber)

        do {
            guard let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) else {
                throw SpeechAnalyzerFailure.noAudioSamples
            }
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
            let timeout = max(30, audioDuration + 30)
            let transcript = try await SpeechAnalyzerSupport.awaitResult(
                resultsTask,
                timeout: timeout
            )
            return try SpeechAnalyzerSupport.validatedTranscript(transcript)
        } catch is CancellationError {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw CancellationError()
        } catch {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw RewriteFailure.transcriptionUnavailable(
                "BuddyWrite could not transcribe this recording with Apple SpeechAnalyzer. \(error.localizedDescription)"
            )
        }
    }
}

@available(macOS 26.0, *)
private final class SpeechAnalyzerStreamingSession: StreamingSpeechTranscriptionSession, @unchecked Sendable {
    private static let maximumPendingAudioBytes = 32 * 1024 * 1024

    private let localeIdentifier: String
    private let queue = DispatchQueue(label: "com.francescooddo.BuddyGrammar.speech-analyzer-input")
    private let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var pendingSamples: [Data] = []
    private var pendingAudioBytes = 0
    private var backlogOverflowed = false
    private var receivedAudioBytes = 0
    private var finished = false
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var processingFailure: (any Error)?
    private var resultsTask: Task<String, Error>?
    private var setupTask: Task<Void, Error>?

    init(localeIdentifier: String) {
        self.localeIdentifier = localeIdentifier
    }

    func start() {
        let task = Task { [self] in
            guard SpeechTranscriber.isAvailable else {
                throw SpeechAnalyzerFailure.unavailable
            }
            guard let locale = await SpeechAnalyzerSupport.resolveLocale(for: localeIdentifier) else {
                throw SpeechAnalyzerFailure.unsupportedLocale(localeIdentifier)
            }

            let transcriber = SpeechAnalyzerSupport.makeTranscriber(locale: locale)
            try await SpeechAnalyzerSupport.ensureAssets(for: transcriber, locale: locale)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: sourceFormat
            ) else {
                throw SpeechAnalyzerFailure.noCompatibleAudioFormat
            }

            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: .init(priority: .userInitiated, modelRetention: .lingering)
            )
            try await analyzer.prepareToAnalyze(in: format)

            let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
            let collector = SpeechAnalyzerSupport.collectResults(from: transcriber)
            do {
                try await analyzer.start(inputSequence: inputSequence)
            } catch {
                builder.finish()
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }

            queue.sync {
                if finished {
                    builder.finish()
                    collector.cancel()
                    Task { await analyzer.cancelAndFinishNow() }
                    return
                }

                self.analyzer = analyzer
                self.inputBuilder = builder
                self.analyzerFormat = format
                self.resultsTask = collector

                let backlog = pendingSamples
                pendingSamples.removeAll(keepingCapacity: false)
                pendingAudioBytes = 0
                for data in backlog {
                    convertAndYieldLocked(data)
                }
            }
        }

        queue.sync {
            setupTask = task
        }
    }

    func appendPCM16(_ data: Data) {
        guard !data.isEmpty else { return }

        queue.async { [self] in
            guard !finished else { return }
            receivedAudioBytes += data.count

            if inputBuilder != nil {
                convertAndYieldLocked(data)
                return
            }

            guard pendingAudioBytes + data.count <= Self.maximumPendingAudioBytes else {
                backlogOverflowed = true
                return
            }
            pendingSamples.append(data)
            pendingAudioBytes += data.count
        }
    }

    func finish() async throws -> String {
        guard let setupTask = queue.sync(execute: { setupTask }) else {
            throw SpeechAnalyzerFailure.sessionNotStarted
        }

        try await withTaskCancellationHandler {
            try await setupTask.value
        } onCancel: {
            self.cancel()
        }

        var activeAnalyzer: SpeechAnalyzer?
        var collector: Task<String, Error>?
        var shouldFallBack = false
        var streamingFailure: (any Error)?
        queue.sync {
            finished = true
            shouldFallBack = backlogOverflowed || receivedAudioBytes == 0
            if !shouldFallBack, processingFailure == nil {
                flushConverterLocked()
            }
            streamingFailure = processingFailure
            inputBuilder?.finish()
            inputBuilder = nil
            activeAnalyzer = analyzer
            collector = resultsTask
        }

        guard !shouldFallBack else {
            cancel()
            throw receivedAudioBytes == 0
                ? SpeechAnalyzerFailure.noAudioSamples
                : SpeechAnalyzerFailure.streamingBacklogOverflow
        }
        if let streamingFailure {
            cancel()
            throw streamingFailure
        }
        guard let activeAnalyzer, let collector else {
            throw SpeechAnalyzerFailure.sessionNotStarted
        }

        do {
            try await activeAnalyzer.finalizeAndFinishThroughEndOfInput()
            let transcript = try await SpeechAnalyzerSupport.awaitResult(collector, timeout: 60)
            let validated = try SpeechAnalyzerSupport.validatedTranscript(transcript)
            queue.sync {
                analyzer = nil
                resultsTask = nil
                converter = nil
            }
            return validated
        } catch is CancellationError {
            cancel()
            throw CancellationError()
        } catch {
            cancel()
            throw error
        }
    }

    func cancel() {
        let task = queue.sync { setupTask }
        task?.cancel()

        queue.async { [self] in
            finished = true
            pendingSamples.removeAll(keepingCapacity: false)
            pendingAudioBytes = 0
            inputBuilder?.finish()
            inputBuilder = nil
            resultsTask?.cancel()
            resultsTask = nil
            converter = nil
            processingFailure = nil
            if let analyzer {
                Task { await analyzer.cancelAndFinishNow() }
            }
            analyzer = nil
        }
    }

    private func convertAndYieldLocked(_ data: Data) {
        guard processingFailure == nil,
              let inputBuilder,
              let analyzerFormat
        else { return }

        guard data.count.isMultiple(of: MemoryLayout<Int16>.size) else {
            recordConversionFailure("The microphone supplied an incomplete PCM sample.")
            return
        }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0 else { return }
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: frameCount
        ), let channel = sourceBuffer.int16ChannelData?[0] else {
            recordConversionFailure("Apple SpeechAnalyzer could not allocate an input buffer.")
            return
        }

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memcpy(channel, baseAddress, Int(frameCount) * MemoryLayout<Int16>.size)
        }
        sourceBuffer.frameLength = frameCount

        if converter == nil {
            converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat)
            converter?.primeMethod = .none
        }
        guard let converter else {
            recordConversionFailure("Apple SpeechAnalyzer could not create an audio converter.")
            return
        }

        let ratio = analyzerFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(
            max(1, (Double(frameCount) * ratio).rounded(.up) + 8)
        )
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: capacity
        ) else {
            recordConversionFailure("Apple SpeechAnalyzer could not allocate an output buffer.")
            return
        }

        let inputProvider = ConverterInputProvider(buffer: sourceBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            if inputProvider.hasSuppliedBuffer {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputProvider.hasSuppliedBuffer = true
            inputStatus.pointee = .haveData
            return inputProvider.buffer
        }

        if status == .error {
            recordConversionFailure(
                conversionError?.localizedDescription ?? "The streaming audio conversion failed."
            )
            return
        }
        if converted.frameLength > 0 {
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }
    }

    private func flushConverterLocked() {
        guard let converter, let analyzerFormat, let inputBuilder else { return }

        for _ in 0..<8 {
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: analyzerFormat,
                frameCapacity: 1_024
            ) else {
                recordConversionFailure("Apple SpeechAnalyzer could not allocate a flush buffer.")
                return
            }

            let inputProvider = ConverterInputProvider(buffer: nil)
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                if inputProvider.hasSuppliedBuffer {
                    inputStatus.pointee = .noDataNow
                } else {
                    inputProvider.hasSuppliedBuffer = true
                    inputStatus.pointee = .endOfStream
                }
                return nil
            }

            if status == .error {
                recordConversionFailure(
                    conversionError?.localizedDescription ?? "The streaming audio converter could not flush."
                )
                return
            }
            if converted.frameLength > 0 {
                inputBuilder.yield(AnalyzerInput(buffer: converted))
            }
            if status != .haveData {
                return
            }
        }
    }

    private func recordConversionFailure(_ message: String) {
        if processingFailure == nil {
            processingFailure = SpeechAnalyzerFailure.audioConversionFailed(message)
        }
    }
}

private final class ConverterInputProvider: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer?
    var hasSuppliedBuffer = false

    init(buffer: AVAudioPCMBuffer?) {
        self.buffer = buffer
    }
}

@available(macOS 26.0, *)
private enum SpeechAnalyzerSupport {
    static func resolveLocale(for localeIdentifier: String) async -> Locale? {
        let requested = Locale(identifier: localeIdentifier)
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return equivalent
        }

        let requestedLanguage = requested.language.languageCode?.identifier
        guard let requestedLanguage else { return nil }
        return await SpeechTranscriber.supportedLocales.first {
            $0.language.languageCode?.identifier == requestedLanguage
        }
    }

    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .transcription)
    }

    static func ensureAssets(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let targetIdentifier = locale.identifier(.bcp47)
        let installedLocales = await SpeechTranscriber.installedLocales
        if !installedLocales.contains(where: { $0.identifier(.bcp47) == targetIdentifier }),
           let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let reservedLocales = await AssetInventory.reservedLocales
        if !reservedLocales.contains(where: { $0.identifier(.bcp47) == targetIdentifier }) {
            do {
                try await AssetInventory.reserve(locale: locale)
            } catch {
                for staleLocale in reservedLocales where staleLocale.identifier(.bcp47) != targetIdentifier {
                    await AssetInventory.release(reservedLocale: staleLocale)
                }
                // Reservation keeps the model warm, but installed assets remain
                // usable when the system declines another reservation.
                _ = try? await AssetInventory.reserve(locale: locale)
            }
        }
    }

    static func collectResults(from transcriber: SpeechTranscriber) -> Task<String, Error> {
        Task {
            var transcript = AttributedString("")
            for try await result in transcriber.results {
                transcript += result.text
            }
            return String(transcript.characters)
        }
    }

    static func awaitResult(
        _ task: Task<String, Error>,
        timeout: TimeInterval
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                task.cancel()
                throw SpeechAnalyzerFailure.resultTimedOut
            }

            guard let result = try await group.next() else {
                throw SpeechAnalyzerFailure.resultTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    static func validatedTranscript(_ transcript: String) throws -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeechAnalyzerFailure.emptyTranscript
        }
        return trimmed
    }
}

@available(macOS 26.0, *)
private enum SpeechAnalyzerFailure: LocalizedError {
    case unavailable
    case unsupportedLocale(String)
    case noCompatibleAudioFormat
    case audioConversionFailed(String)
    case noAudioSamples
    case emptyTranscript
    case resultTimedOut
    case sessionNotStarted
    case streamingBacklogOverflow

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple SpeechAnalyzer is unavailable on this Mac."
        case .unsupportedLocale(let identifier):
            "Apple SpeechAnalyzer does not support \(identifier)."
        case .noCompatibleAudioFormat:
            "Apple SpeechAnalyzer could not find a compatible audio format."
        case .audioConversionFailed(let message):
            message
        case .noAudioSamples:
            "No microphone audio reached Apple SpeechAnalyzer."
        case .emptyTranscript:
            "BuddyWrite could not hear any speech in the recording."
        case .resultTimedOut:
            "Apple SpeechAnalyzer did not finish in time."
        case .sessionNotStarted:
            "The live Apple SpeechAnalyzer session did not start."
        case .streamingBacklogOverflow:
            "The live transcription buffer filled while the speech model was preparing."
        }
    }
}

@MainActor
final class WhisperKitSpeechEngine: FallbackSpeechTranscriptionEngine {
    private enum StorageKey {
        static let cachedModelFolderPath = "BuddyGrammar.voice.whisperModelFolderPath"
    }

    private let modelID: VoiceFallbackModelID
    private let defaults: UserDefaults
    private var whisperKit: WhisperKit?
    private var cachedModelFolderPath: String?

    init(modelID: VoiceFallbackModelID = .whisperBase, defaults: UserDefaults = .standard) {
        self.modelID = modelID
        self.defaults = defaults

        if let persistedPath = defaults.string(forKey: StorageKey.cachedModelFolderPath),
           FileManager.default.fileExists(atPath: persistedPath) {
            self.cachedModelFolderPath = persistedPath
        } else {
            defaults.removeObject(forKey: StorageKey.cachedModelFolderPath)
        }
    }

    func isAvailable(for localeIdentifier: String) async -> Bool {
        true
    }

    func isPrepared() async -> Bool {
        whisperKit != nil || cachedModelFolderPath != nil
    }

    func preload() async throws {
        if whisperKit != nil {
            return
        }

        if cachedModelFolderPath != nil {
            do {
                whisperKit = try await loadWhisperKit(allowDownload: false)
                return
            } catch {
                clearCachedModelFolder()
            }
        }

        whisperKit = try await loadWhisperKit(allowDownload: true)
    }

    func transcribe(audioURL: URL, localeIdentifier: String) async throws -> String {
        if whisperKit == nil, cachedModelFolderPath != nil {
            do {
                whisperKit = try await loadWhisperKit(allowDownload: false)
            } catch {
                clearCachedModelFolder()
            }
        }

        guard let whisperKit else {
            throw RewriteFailure.transcriptionUnavailable(
                "Download the local Whisper fallback model in Settings before using dictation on this Mac."
            )
        }

        let languageCode = Self.whisperLanguageCode(for: localeIdentifier)
        let decodeOptions = DecodingOptions(
            language: languageCode,
            detectLanguage: languageCode == nil,
            chunkingStrategy: .vad
        )
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: decodeOptions
        )
        guard !results.isEmpty else {
            throw RewriteFailure.transcriptionUnavailable("BuddyWrite could not transcribe the recorded audio with Whisper.")
        }

        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if text.isEmpty {
            throw RewriteFailure.transcriptionUnavailable("BuddyWrite could not hear any speech in the recording.")
        }
        return text
    }

    static func whisperLanguageCode(for localeIdentifier: String) -> String? {
        let code = Locale(identifier: localeIdentifier)
            .language
            .languageCode?
            .identifier
            .lowercased()
        guard let code, Constants.languageCodes.contains(code) else { return nil }
        return code
    }

    private func loadWhisperKit(allowDownload: Bool) async throws -> WhisperKit {
        let whisperKit = try await WhisperKit(
            WhisperKitConfig(
                model: modelID.whisperKitModelName,
                modelFolder: cachedModelFolderPath,
                verbose: false,
                prewarm: false,
                load: true,
                download: allowDownload
            )
        )

        if let modelFolderPath = whisperKit.modelFolder?.path {
            cachedModelFolderPath = modelFolderPath
            defaults.set(modelFolderPath, forKey: StorageKey.cachedModelFolderPath)
        }

        return whisperKit
    }

    private func clearCachedModelFolder() {
        cachedModelFolderPath = nil
        defaults.removeObject(forKey: StorageKey.cachedModelFolderPath)
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

        Task { [weak self] in
            guard let self else { return }
            if await self.fallbackEngine.isPrepared() {
                self.status = .init(state: .loaded, errorMessage: nil)
            }
        }
    }

    func appleOnDeviceAvailable(for localeIdentifier: String) async -> Bool {
        await appleEngine.isAvailable(for: localeIdentifier)
    }

    func resolveRoute(for localeIdentifier: String) async throws -> VoiceTranscriptionRoute {
        if await appleEngine.isAvailable(for: localeIdentifier) {
            let requiresAuthorization = await appleEngine
                .requiresSpeechRecognitionAuthorization(for: localeIdentifier)
            return .apple(requiresSpeechRecognitionAuthorization: requiresAuthorization)
        }

        if await fallbackEngine.isPrepared() {
            return .whisper
        }

        let message = Self.missingFallbackMessage
        lastErrorMessage = message
        if status.state == .notDownloaded {
            status = .init(state: .notDownloaded, errorMessage: message)
        }
        throw RewriteFailure.transcriptionUnavailable(message)
    }

    func makeStreamingSession(
        for localeIdentifier: String
    ) async -> (any StreamingSpeechTranscriptionSession)? {
        await appleEngine.makeStreamingSession(localeIdentifier: localeIdentifier)
    }

    func fallbackModelIsPrepared() async -> Bool {
        await fallbackEngine.isPrepared()
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

    func transcribe(
        audioURL: URL,
        localeIdentifier: String,
        route: VoiceTranscriptionRoute? = nil,
        streamingSession: (any StreamingSpeechTranscriptionSession)? = nil
    ) async throws -> String {
        var appleFailure: Error?
        let shouldTryApple = route != .whisper

        if shouldTryApple, let streamingSession {
            do {
                let transcript = try await streamingSession.finish()
                lastErrorMessage = nil
                return transcript
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                streamingSession.cancel()
                appleFailure = error
            }
        }

        if shouldTryApple, await appleEngine.isAvailable(for: localeIdentifier) {
            do {
                let transcript = try await appleEngine.transcribe(
                    audioURL: audioURL,
                    localeIdentifier: localeIdentifier
                )
                lastErrorMessage = nil
                return transcript
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                appleFailure = error
            }
        }

        let fallbackPrepared = await fallbackEngine.isPrepared()
        if !fallbackPrepared {
            if let appleFailure {
                let message = "Apple on-device transcription failed. \(appleFailure.localizedDescription)"
                lastErrorMessage = message
                throw RewriteFailure.transcriptionUnavailable(message)
            }

            let message = Self.missingFallbackMessage
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
            await recordFallbackFailure(message)
            throw failure
        } catch {
            let message = "BuddyWrite could not transcribe the recorded audio. \(error.localizedDescription)"
            await recordFallbackFailure(message)
            throw RewriteFailure.transcriptionUnavailable(message)
        }
    }

    private func recordFallbackFailure(_ message: String) async {
        let fallbackStillPrepared = await fallbackEngine.isPrepared()
        status = fallbackStillPrepared
            ? .init(state: .loaded, errorMessage: nil)
            : .init(state: .notDownloaded, errorMessage: message)
        lastErrorMessage = message
    }

    private static let missingFallbackMessage =
        "Apple on-device speech is unavailable for this language on this Mac. "
        + "Download the Whisper fallback model in Settings to keep dictation fully local."
}
