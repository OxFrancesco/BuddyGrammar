import AVFoundation
import AVKit
import BuddyGrammarKit
import Observation
import UIKit

/// Hosts the `AVSampleBufferDisplayLayer` that backs the Picture in Picture
/// companion window.
final class CompanionSampleBufferView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var sampleBufferLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        sampleBufferLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Keeps the app alive off-screen with a Picture in Picture window so the
/// keyboard can start dictation instantly, without bouncing the user into the
/// app. While enabled it writes a heartbeat into the App Group so the keyboard
/// knows the companion can pick up start/stop signals sent over Darwin
/// notifications.
@MainActor
@Observable
final class DictationCompanionController: NSObject {
    enum CompanionStatus: Equatable {
        case idle
        case recording(startedAt: Date)
        case processing
    }

    @ObservationIgnored var onStartRequested: (@MainActor () -> Void)?
    @ObservationIgnored var onStopRequested: (@MainActor () -> Void)?

    private(set) var isEnabled = false
    private(set) var isPictureInPictureActive = false

    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    let layerHostView = CompanionSampleBufferView()

    @ObservationIgnored private let preferences: SharedPreferences?
    @ObservationIgnored private var pipController: AVPictureInPictureController?
    @ObservationIgnored private var signalObserver: DictationCompanionObserver?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var frameRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var status: CompanionStatus = .idle

    init(preferences: SharedPreferences?) {
        self.preferences = preferences
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        if enabled {
            guard Self.isSupported else { return }
            isEnabled = true
            preparePictureInPictureController()
            startSignalObserver()
            startHeartbeat()
            startFrameRefresh()
            renderFrame()
        } else {
            isEnabled = false
            heartbeatTask?.cancel()
            heartbeatTask = nil
            frameRefreshTask?.cancel()
            frameRefreshTask = nil
            signalObserver = nil
            preferences?.clearCompanionHeartbeat()
            if pipController?.isPictureInPictureActive == true {
                pipController?.stopPictureInPicture()
            }
        }
    }

    func update(status: CompanionStatus) {
        guard status != self.status else { return }
        self.status = status
        renderFrame()
    }

    func startPictureInPicture() {
        guard isEnabled, let pipController,
              !pipController.isPictureInPictureActive else { return }
        renderFrame()
        pipController.startPictureInPicture()
    }

    private func preparePictureInPictureController() {
        guard pipController == nil else { return }
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layerHostView.sampleBufferLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        pipController = controller

        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
    }

    private func startSignalObserver() {
        signalObserver = DictationCompanionObserver { [weak self] signal in
            Task { @MainActor [weak self] in
                guard let self, isEnabled else { return }
                switch signal {
                case .startRequested:
                    onStartRequested?()
                case .stopRequested:
                    onStopRequested?()
                }
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [preferences] in
            while !Task.isCancelled {
                preferences?.recordCompanionHeartbeat()
                try? await Task.sleep(
                    for: .seconds(BuddyGrammarConfiguration.companionHeartbeatInterval)
                )
            }
        }
    }

    private func startFrameRefresh() {
        frameRefreshTask?.cancel()
        frameRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.renderFrame()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Frame rendering

    // Square frames keep the system PiP window as small as possible.
    private static let frameSize = CGSize(width: 240, height: 240)

    private func renderFrame(at date: Date = .now) {
        guard isEnabled,
              let sampleBuffer = makeSampleBuffer(at: date) else { return }
        let renderer = layerHostView.sampleBufferLayer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        guard renderer.isReadyForMoreMediaData else { return }
        renderer.enqueue(sampleBuffer)
    }

    private func makeSampleBuffer(at date: Date) -> CMSampleBuffer? {
        let width = Int(Self.frameSize.width)
        let height = Int(Self.frameSize.height)

        var pixelBufferOut: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBufferOut
        )
        guard let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        drawFrame(at: date, in: CGRect(origin: .zero, size: Self.frameSize))
        UIGraphicsPopContext()

        var formatDescriptionOut: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescriptionOut
        )
        guard let formatDescription = formatDescriptionOut else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBufferOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBufferOut
        )
        guard let sampleBuffer = sampleBufferOut else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ) as? [NSMutableDictionary], let first = attachments.first {
            first[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sampleBuffer
    }

    private func drawFrame(at date: Date, in rect: CGRect) {
        let symbolName: String
        let tint: UIColor
        let title: String
        let subtitle: String

        switch status {
        case .idle:
            symbolName = "mic.fill"
            tint = .systemGray
            title = "BuddyGrammar"
            subtitle = "Quick dictation ready"
        case .recording(let startedAt):
            symbolName = "record.circle.fill"
            tint = .systemRed
            title = "Listening…"
            let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
            subtitle = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        case .processing:
            symbolName = "waveform"
            tint = .systemIndigo
            title = "Transcribing…"
            subtitle = "Polishing your words"
        }

        UIColor(white: 0.09, alpha: 1).setFill()
        UIRectFill(rect)

        let symbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 52,
            weight: .semibold
        )
        if let symbol = UIImage(systemName: symbolName, withConfiguration: symbolConfiguration)?
            .withTintColor(tint, renderingMode: .alwaysOriginal) {
            let symbolRect = CGRect(
                x: rect.midX - symbol.size.width / 2,
                y: 52,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symbolRect)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        (title as NSString).draw(
            in: CGRect(x: 0, y: 132, width: rect.width, height: 32),
            withAttributes: titleAttributes
        )

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .medium),
            .foregroundColor: UIColor(white: 1, alpha: 0.65),
            .paragraphStyle: paragraphStyle,
        ]
        (subtitle as NSString).draw(
            in: CGRect(x: 0, y: 170, width: rect.width, height: 26),
            withAttributes: subtitleAttributes
        )
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension DictationCompanionController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isPictureInPictureActive = true
            self.renderFrame()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isPictureInPictureActive = false
        }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension DictationCompanionController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
