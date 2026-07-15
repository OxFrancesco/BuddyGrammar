@preconcurrency import AVFoundation
import Foundation

typealias PCM16SampleHandler = @Sendable (Data) -> Void

protocol AudioBufferProcessing: AnyObject, Sendable {
    nonisolated func process(_ inputBuffer: AVAudioPCMBuffer)
}

enum AudioTapBlockFactory {
    /// AVAudioEngine invokes tap blocks on a real-time Core Audio queue. Build
    /// the closure from an explicitly nonisolated context so Swift does not
    /// insert a main-executor precondition around the callback.
    nonisolated static func make(
        processor: any AudioBufferProcessing
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            processor.process(buffer)
        }
    }
}

@MainActor
protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording() -> URL?
}

@MainActor
protocol PCMStreamingAudioRecording: AudioRecording {
    func setPCM16SampleHandler(_ handler: PCM16SampleHandler?)
}

@MainActor
final class AudioRecordingService: AudioRecording, PCMStreamingAudioRecording {
    private var audioEngine: AVAudioEngine?
    private var capturePipeline: AudioCapturePipeline?
    private var outputURL: URL?
    private var sampleHandler: PCM16SampleHandler?

    var isRecording: Bool {
        audioEngine?.isRunning == true
    }

    func setPCM16SampleHandler(_ handler: PCM16SampleHandler?) {
        sampleHandler = handler
    }

    func startRecording() throws {
        guard !isRecording else { return }

        let outputURL = Self.makeOutputURL()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RewriteFailure.voiceRecordingFailed("BuddyWrite could not read a valid microphone format.")
        }

        let pipeline: AudioCapturePipeline
        do {
            pipeline = try AudioCapturePipeline(
                outputURL: outputURL,
                inputFormat: inputFormat,
                sampleHandler: sampleHandler
            )
        } catch {
            throw RewriteFailure.voiceRecordingFailed(
                "BuddyWrite could not prepare the audio recorder. \(error.localizedDescription)"
            )
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: inputFormat,
            block: AudioTapBlockFactory.make(processor: pipeline)
        )

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            pipeline.cancel()
            try? FileManager.default.removeItem(at: outputURL)
            throw RewriteFailure.voiceRecordingFailed(
                "BuddyWrite could not start recording audio. \(error.localizedDescription)"
            )
        }

        self.audioEngine = engine
        self.capturePipeline = pipeline
        self.outputURL = outputURL
    }

    func stopRecording() -> URL? {
        guard let engine = audioEngine,
              let pipeline = capturePipeline,
              let outputURL
        else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        audioEngine = nil
        capturePipeline = nil
        self.outputURL = nil

        guard pipeline.finish() else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        return outputURL
    }

    private static func makeOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("buddywrite-dictation-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }
}

private final class AudioCapturePipeline: AudioBufferProcessing, @unchecked Sendable {
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let lock = NSLock()
    private let sampleHandler: PCM16SampleHandler?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var frameCount: AVAudioFramePosition = 0
    private var processingError: Error?
    private var isFinished = false

    init(
        outputURL: URL,
        inputFormat: AVAudioFormat,
        sampleHandler: PCM16SampleHandler?
    ) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        converter.primeMethod = .none

        self.converter = converter
        self.sampleHandler = sampleHandler
        self.audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: Self.targetFormat.settings,
            commonFormat: Self.targetFormat.commonFormat,
            interleaved: Self.targetFormat.isInterleaved
        )
    }

    func process(_ inputBuffer: AVAudioPCMBuffer) {
        lock.lock()
        if !isFinished, processingError == nil {
            do {
                if let outputBuffer = try convert(inputBuffer), outputBuffer.frameLength > 0 {
                    try consume(outputBuffer)
                }
            } catch {
                processingError = error
            }
        }
        lock.unlock()
    }

    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished else { return false }
        isFinished = true
        if processingError == nil {
            do {
                try flushConverter()
            } catch {
                processingError = error
            }
        }
        audioFile = nil
        converter = nil
        return processingError == nil && frameCount > 0
    }

    func cancel() {
        lock.lock()
        isFinished = true
        audioFile = nil
        converter = nil
        lock.unlock()
    }

    private func convert(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        guard let converter else { return nil }

        let ratio = Self.targetFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(
            max(1, (Double(inputBuffer.frameLength) * ratio).rounded(.up) + 8)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat,
            frameCapacity: capacity
        ) else {
            throw AudioCaptureError.bufferAllocationFailed
        }

        let inputProvider = AudioConverterInputProvider(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if inputProvider.hasSuppliedBuffer {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputProvider.hasSuppliedBuffer = true
            inputStatus.pointee = .haveData
            return inputProvider.buffer
        }

        if status == .error {
            throw conversionError ?? AudioCaptureError.conversionFailed
        }
        return outputBuffer
    }

    private func flushConverter() throws {
        guard let converter else { return }

        for _ in 0..<8 {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: Self.targetFormat,
                frameCapacity: 1_024
            ) else {
                throw AudioCaptureError.bufferAllocationFailed
            }

            let inputProvider = AudioConverterInputProvider(buffer: nil)
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                if inputProvider.hasSuppliedBuffer {
                    inputStatus.pointee = .noDataNow
                } else {
                    inputProvider.hasSuppliedBuffer = true
                    inputStatus.pointee = .endOfStream
                }
                return nil
            }

            if status == .error {
                throw conversionError ?? AudioCaptureError.conversionFailed
            }
            if outputBuffer.frameLength > 0 {
                try consume(outputBuffer)
            }
            if status != .haveData {
                return
            }
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) throws {
        try audioFile?.write(from: buffer)
        frameCount += AVAudioFramePosition(buffer.frameLength)
        if let data = Self.data(from: buffer), !data.isEmpty {
            // Keep delivery inside the lock so stopRecording cannot finish the
            // analyzer before the last callback has queued its samples.
            sampleHandler?(data)
        }
    }

    private static func data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0,
              let channel = buffer.int16ChannelData?[0]
        else { return nil }

        return Data(
            bytes: channel,
            count: Int(buffer.frameLength) * MemoryLayout<Int16>.size
        )
    }
}

private final class AudioConverterInputProvider: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer?
    var hasSuppliedBuffer = false

    init(buffer: AVAudioPCMBuffer?) {
        self.buffer = buffer
    }
}

private enum AudioCaptureError: LocalizedError {
    case converterUnavailable
    case bufferAllocationFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .converterUnavailable:
            "The microphone format could not be converted for speech recognition."
        case .bufferAllocationFailed:
            "An audio conversion buffer could not be created."
        case .conversionFailed:
            "Microphone audio conversion failed."
        }
    }
}
