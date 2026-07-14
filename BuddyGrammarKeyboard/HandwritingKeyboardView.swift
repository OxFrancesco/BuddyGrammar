import BuddyGrammarKit
import SwiftUI
import UIKit
import Vision

private struct HandwritingRecognitionAttempt: Sendable {
    let candidates: [String]
    let confidence: Float
    let imageData: Data?
}

@MainActor
@Observable
final class HandwritingRecognizer {
    var strokes: [[CGPoint]] = []
    var currentStroke: [CGPoint] = []
    private(set) var candidates: [String] = []
    private(set) var isRecognizing = false
    private(set) var isUsingCloud = false
    private(set) var recognitionFailed = false

    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var canvasSize: CGSize = .zero
    @ObservationIgnored private var recognitionRevision: UInt64 = 0
    @ObservationIgnored private var cloudFallback: ((Data) async throws -> String?)?

    var hasContent: Bool {
        !strokes.isEmpty || !currentStroke.isEmpty
    }

    func updateCanvasSize(_ size: CGSize) {
        canvasSize = size
    }

    func configureCloudFallback(_ fallback: @escaping (Data) async throws -> String?) {
        cloudFallback = fallback
    }

    func appendPoint(_ point: CGPoint) {
        currentStroke.append(point)
        debounceTask?.cancel()
    }

    func endStroke() {
        guard !currentStroke.isEmpty else { return }
        strokes.append(currentStroke)
        currentStroke = []
        recognitionFailed = false
        recognitionRevision &+= 1
        scheduleRecognition(revision: recognitionRevision)
    }

    func clear() {
        debounceTask?.cancel()
        recognitionRevision &+= 1
        strokes = []
        currentStroke = []
        candidates = []
        isRecognizing = false
        isUsingCloud = false
        recognitionFailed = false
    }

    private func scheduleRecognition(revision: UInt64) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            await self?.recognize(revision: revision)
        }
    }

    private func recognize(revision: UInt64) async {
        guard !strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }
        isRecognizing = true
        isUsingCloud = false
        recognitionFailed = false

        let strokes = strokes
        let attempt = await Task.detached(priority: .userInitiated) {
            Self.recognizeText(strokes: strokes)
        }.value

        guard !Task.isCancelled, revision == recognitionRevision else { return }
        let localCandidates = attempt.candidates
        let shouldAskCloud = localCandidates.isEmpty
            || attempt.confidence < Self.minimumLocalConfidence
        if shouldAskCloud, let imageData = attempt.imageData, let cloudFallback {
            isUsingCloud = true
            do {
                let cloudText = try await cloudFallback(imageData)
                guard !Task.isCancelled, revision == recognitionRevision else { return }
                if let cloudText,
                   !cloudText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    candidates = ([cloudText] + localCandidates).uniqued()
                    isRecognizing = false
                    isUsingCloud = false
                    return
                }
            } catch {
                guard !Task.isCancelled, revision == recognitionRevision else { return }
            }
        }

        if !localCandidates.isEmpty {
            candidates = localCandidates
            isRecognizing = false
            isUsingCloud = false
            return
        }

        candidates = []
        isRecognizing = false
        isUsingCloud = false
        recognitionFailed = true
    }

    private nonisolated static func recognizeText(
        strokes: [[CGPoint]]
    ) -> HandwritingRecognitionAttempt {
        let targetSize = CGSize(width: 640, height: 256)
        guard let layout = HandwritingStrokeNormalizer.normalized(
            strokes: strokes,
            targetSize: targetSize,
            padding: 24
        ) else {
            return HandwritingRecognitionAttempt(
                candidates: [],
                confidence: 0,
                imageData: nil
            )
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            UIColor.black.setStroke()
            UIColor.black.setFill()
            for stroke in layout.strokes where !stroke.isEmpty {
                if stroke.count == 1, let point = stroke.first {
                    let radius = layout.dotDiameter / 2
                    context.cgContext.fillEllipse(
                        in: CGRect(
                            x: point.x - radius,
                            y: point.y - radius,
                            width: layout.dotDiameter,
                            height: layout.dotDiameter
                        )
                    )
                    continue
                }
                let path = UIBezierPath()
                path.lineWidth = layout.lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: stroke[0])
                for point in stroke.dropFirst() {
                    path.addLine(to: point)
                }
                path.stroke()
            }
        }

        guard let cgImage = image.cgImage else {
            return HandwritingRecognitionAttempt(
                candidates: [],
                confidence: 0,
                imageData: nil
            )
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.02
        let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
        let preferredLanguages = preferredRecognitionLanguages(supported: supportedLanguages)
        request.recognitionLanguages = preferredLanguages
        request.automaticallyDetectsLanguage = preferredLanguages.count > 1

        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return HandwritingRecognitionAttempt(
                candidates: [],
                confidence: 0,
                imageData: image.pngData()
            )
        }

        let observations = request.results ?? []
        guard !observations.isEmpty else {
            return HandwritingRecognitionAttempt(
                candidates: [],
                confidence: 0,
                imageData: image.pngData()
            )
        }

        if observations.count == 1 {
            let recognized = observations[0].topCandidates(3)
            return HandwritingRecognitionAttempt(
                candidates: recognized.map(\.string),
                confidence: recognized.first?.confidence ?? 0,
                imageData: image.pngData()
            )
        }

        let recognized = observations.compactMap { $0.topCandidates(1).first }
        let joined = recognized
            .map(\.string)
            .joined(separator: " ")
        return HandwritingRecognitionAttempt(
            candidates: joined.isEmpty ? [] : [joined],
            confidence: recognized.map(\.confidence).min() ?? 0,
            imageData: image.pngData()
        )
    }

    private nonisolated static let minimumLocalConfidence: Float = 0.65

    private nonisolated static func preferredRecognitionLanguages(
        supported: [String]
    ) -> [String] {
        var selected: [String] = []
        for preferred in Locale.preferredLanguages {
            if let exact = supported.first(where: {
                $0.caseInsensitiveCompare(preferred) == .orderedSame
            }) {
                selected.append(exact)
            } else {
                let language = preferred.split(separator: "-").first
                if let language,
                   let compatible = supported.first(where: {
                       $0.split(separator: "-").first?.caseInsensitiveCompare(language)
                           == .orderedSame
                   }) {
                    selected.append(compatible)
                }
            }
        }
        if selected.isEmpty, let english = supported.first(where: { $0.hasPrefix("en") }) {
            selected.append(english)
        }
        return Array(selected.uniqued().prefix(3))
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct HandwritingKeyboardLayer: View {
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    @State private var recognizer = HandwritingRecognizer()

    var body: some View {
        VStack(spacing: 6) {
            candidateBar

            HandwritingCanvas(recognizer: recognizer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: metrics.keySpacing) {
                Button("ABC") {
                    model.setLayout(.letters)
                }
                .font(.callout)
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth, height: 38)
                )
                .accessibilityLabel("Show letters")
                .accessibilityIdentifier("keyboard.layout")

                Button("Clear", action: recognizer.clear)
                    .font(.callout)
                    .buttonStyle(
                        KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth * 1.2, height: 38)
                    )
                    .accessibilityLabel("Clear handwriting")
                    .accessibilityIdentifier("keyboard.handwriting.clear")

                Button(action: model.insertSpace) {
                    Text("space")
                        .font(.callout)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(KeyboardKeyButtonStyle())
                .accessibilityIdentifier("keyboard.space")

                Button(action: model.deleteBackward) {
                    Image(systemName: "delete.left")
                        .frame(width: metrics.wideFunctionKeyWidth, height: 38)
                }
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth, height: 38)
                )
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("keyboard.delete")

                Button(action: model.insertReturn) {
                    Image(systemName: "return")
                        .frame(width: metrics.wideFunctionKeyWidth, height: 38)
                }
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth, height: 38)
                )
                .accessibilityLabel("Return")
                .accessibilityIdentifier("keyboard.return")
            }
        }
        .onAppear {
            recognizer.configureCloudFallback { [weak model] imageData in
                try await model?.recognizeHandwriting(imageData)
            }
        }
    }

    private var candidateBar: some View {
        HStack(spacing: 6) {
            if recognizer.isRecognizing {
                ProgressView()
                    .controlSize(.small)
                Text(recognizer.isUsingCloud ? "Asking AI…" : "Reading on device…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if recognizer.recognitionFailed {
                Text("Couldn't read that")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("keyboard.handwriting.error")
            } else if recognizer.candidates.isEmpty {
                Text(recognizer.hasContent ? "Keep writing…" : "Write below, then tap a suggestion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recognizer.candidates.prefix(3), id: \.self) { candidate in
                    Button {
                        model.insertRecognizedText(candidate)
                        recognizer.clear()
                    } label: {
                        Text(candidate)
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(KeyboardAccessoryButtonStyle())
                    .accessibilityLabel("Insert \(candidate)")
                    .accessibilityIdentifier("keyboard.handwriting.candidate.\(candidate)")
                }
            }
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity)
    }
}

private struct HandwritingCanvas: View {
    let recognizer: HandwritingRecognizer

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .systemBackground))

                strokesPath(recognizer.strokes + [recognizer.currentStroke])
                    .stroke(
                        Color.primary,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )

                dotsPath(recognizer.strokes + [recognizer.currentStroke])
                    .fill(Color.primary)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        recognizer.updateCanvasSize(proxy.size)
                        recognizer.appendPoint(value.location)
                    }
                    .onEnded { _ in
                        recognizer.endStroke()
                    }
            )
            .onAppear {
                recognizer.updateCanvasSize(proxy.size)
            }
        }
        .accessibilityLabel("Handwriting canvas")
        .accessibilityIdentifier("keyboard.handwriting.canvas")
    }

    private func strokesPath(_ strokes: [[CGPoint]]) -> Path {
        Path { path in
            for stroke in strokes where stroke.count > 1 {
                path.move(to: stroke[0])
                for point in stroke.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func dotsPath(_ strokes: [[CGPoint]]) -> Path {
        Path { path in
            for stroke in strokes where stroke.count == 1 {
                guard let point = stroke.first else { continue }
                path.addEllipse(
                    in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
                )
            }
        }
    }
}
