import SwiftUI

struct KeyboardMetrics: Equatable {
    let width: CGFloat
    let bodyHeight: CGFloat

    var keySpacing: CGFloat { 5 }
    var rowSpacing: CGFloat { 7 }
    var horizontalPadding: CGFloat { 4 }
    var suggestionBarHeight: CGFloat { 44 }
    var keyHeight: CGFloat { max(30, (bodyHeight - 3 * rowSpacing) / 4) }
    var letterKeyWidth: CGFloat {
        max(20, (width - 2 * horizontalPadding - 9 * keySpacing) / 10)
    }
    var wideFunctionKeyWidth: CGFloat { letterKeyWidth * 1.3 }

    init(size: CGSize) {
        width = size.width
        bodyHeight = max(120, size.height - 44 - 14)
    }

    init(width: CGFloat, bodyHeight: CGFloat) {
        self.width = width
        self.bodyHeight = bodyHeight
    }
}

struct KeyboardRootView: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge

    var body: some View {
        GeometryReader { proxy in
            let metrics = KeyboardMetrics(size: proxy.size)

            VStack(spacing: 6) {
                KeyboardSuggestionBar(model: model)
                    .frame(height: metrics.suggestionBarHeight)

                Group {
                    switch model.layoutMode {
                    case .letters:
                        LetterKeyboardLayer(model: model, controllerBridge: controllerBridge, metrics: metrics)
                    case .numbers:
                        SymbolKeyboardLayer(model: model, controllerBridge: controllerBridge, metrics: metrics, plane: .numbers)
                    case .symbols:
                        SymbolKeyboardLayer(model: model, controllerBridge: controllerBridge, metrics: metrics, plane: .symbols)
                    case .latex:
                        LatexKeyboardLayer(model: model, metrics: metrics)
                    case .emoji:
                        EmojiKeyboardLayer(model: model, metrics: metrics)
                    case .handwriting:
                        HandwritingKeyboardLayer(model: model, metrics: metrics)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .background(Color(uiColor: .systemGray5))
    }
}

private struct KeyboardSuggestionBar: View {
    let model: KeyboardModel

    var body: some View {
        HStack(spacing: 6) {
            if model.canUndoCorrection {
                Button(action: model.undoLastCorrection) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(KeyboardAccessoryButtonStyle())
                .accessibilityIdentifier("keyboard.undo")
                .accessibilityHint("Restores the text from before the star correction")
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if model.isStatusPresented {
                StatusIndicator(status: model.status)
                    .frame(maxWidth: .infinity)
            } else {
                SuggestionSlots(model: model)
                    .frame(maxWidth: .infinity)
            }

            Button {
                model.setLayout(.latex)
            } label: {
                Image(systemName: "x.squareroot")
                    .frame(width: 34, height: 32)
            }
            .buttonStyle(KeyboardAccessoryButtonStyle())
            .accessibilityIdentifier("keyboard.latex")
            .accessibilityLabel("LaTeX keys")

            Button {
                model.setLayout(.handwriting)
            } label: {
                Image(systemName: "pencil.and.scribble")
                    .frame(width: 34, height: 32)
            }
            .buttonStyle(KeyboardAccessoryButtonStyle())
            .accessibilityIdentifier("keyboard.handwriting")
            .accessibilityLabel("Handwriting input")

            Button(action: model.toggleDictation) {
                Group {
                    if model.dictationPhase == .processing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: dictationIcon)
                    }
                }
                .frame(width: 38, height: 32)
            }
            .buttonStyle(
                KeyboardAccessoryButtonStyle(
                    isProminent: model.dictationPhase == .recording,
                    prominentColor: .red
                )
            )
            .disabled(model.dictationPhase == .processing)
            .accessibilityIdentifier("keyboard.mic")
            .accessibilityLabel(
                model.dictationPhase == .recording
                    ? "Stop voice dictation"
                    : "Start voice dictation"
            )
            .accessibilityHint("Records with BuddyGrammar and inserts the transcript here")

            Button(action: model.correctCurrentText) {
                Group {
                    if model.status == .correcting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "star.fill")
                    }
                }
                .frame(width: 38, height: 32)
            }
            .buttonStyle(KeyboardAccessoryButtonStyle(isProminent: true))
            .disabled(model.status == .correcting)
            .accessibilityIdentifier("keyboard.star")
            .accessibilityLabel("Correct text")
            .accessibilityHint("Corrects selected text, or the sentence immediately before the cursor")
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: model.canUndoCorrection)
    }

    private var dictationIcon: String {
        switch model.dictationPhase {
        case .idle, .launching:
            "waveform.badge.mic"
        case .recording:
            "stop.fill"
        case .processing:
            "waveform"
        }
    }
}

private struct SuggestionSlots: View {
    let model: KeyboardModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.suggestions) { suggestion in
                Button {
                    model.insertSuggestion(suggestion)
                } label: {
                    Text(suggestion.display)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(KeyboardAccessoryButtonStyle())
                .accessibilityIdentifier("keyboard.suggestion.\(suggestion.id)")
                .accessibilityLabel("Insert \(suggestion.display)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatusIndicator: View {
    let status: KeyboardStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .accessibilityHidden(true)
            Text(status.message)
                .font(.caption2)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(status.isError ? Color.orange : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keyboard.status")
    }

    private var iconName: String {
        switch status {
        case .correcting:
            "hourglass"
        case .corrected, .correctionUndone, .transcriptInserted:
            "checkmark.circle.fill"
        case .openingDictation:
            "arrow.up.forward.app"
        case .startingDictation:
            "dot.radiowaves.left.and.right"
        case .dictationRecording:
            "mic.fill"
        case .dictationProcessing:
            "waveform"
        case .ready:
            "star"
        case .fullAccessRequired:
            "lock"
        case .cloudConsentRequired:
            "hand.raised"
        case .noText, .noPendingTranscript, .staleContext, .error:
            "exclamationmark.triangle"
        }
    }
}

private struct LetterKeyboardLayer: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge
    let metrics: KeyboardMetrics

    @State private var keyFrames: [String: CGRect] = [:]
    @State private var swipePoints: [CGPoint] = []
    @State private var swipeTrace: [Character] = []

    private static let coordinateSpace = "keyboard.swipeSpace"

    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            CharacterRow(characters: LetterKeys.top, model: model, metrics: metrics)
            CharacterRow(characters: LetterKeys.middle, model: model, metrics: metrics)
                .padding(.horizontal, metrics.letterKeyWidth / 2)
            HStack(spacing: metrics.keySpacing) {
                ShiftKey(model: model, metrics: metrics)
                CharacterRow(characters: LetterKeys.bottom, model: model, metrics: metrics)
                DeleteKey(model: model, metrics: metrics)
            }
            KeyboardControlRow(model: model, controllerBridge: controllerBridge, metrics: metrics)
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(KeyFramePreferenceKey.self) { keyFrames = $0 }
        .overlay {
            SwipeTrail(points: swipePoints)
                .allowsHitTesting(false)
        }
        .simultaneousGesture(swipeGesture)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if swipePoints.isEmpty {
                    appendSwipeSample(at: value.startLocation)
                }
                appendSwipeSample(at: value.location)
            }
            .onEnded { _ in
                let points = swipePoints
                let trace = swipeTrace
                swipePoints = []
                swipeTrace = []
                guard Set(trace).count >= 2 else { return }
                let path = points.compactMap(keySpacePoint(for:))
                guard path.count >= 2 else { return }
                model.commitSwipe(path: path)
            }
    }

    /// Converts a point in the keyboard's coordinate space into the engine's
    /// key-space (1 unit = 1 key width), anchored on the q/p/z key centers.
    private func keySpacePoint(for point: CGPoint) -> CGPoint? {
        guard let q = keyFrames["q"], let p = keyFrames["p"], let z = keyFrames["z"] else {
            return nil
        }
        let qCenter = CGPoint(x: q.midX, y: q.midY)
        let xScale = (p.midX - qCenter.x) / 9
        let yScale = (z.midY - qCenter.y) / 2
        guard xScale > 0, yScale > 0 else { return nil }
        return CGPoint(
            x: (point.x - qCenter.x) / xScale,
            y: (point.y - qCenter.y) / yScale
        )
    }

    private func appendSwipeSample(at point: CGPoint) {
        swipePoints.append(point)
        guard let key = nearestKey(to: point), swipeTrace.last != key else { return }
        swipeTrace.append(key)
    }

    private func nearestKey(to point: CGPoint) -> Character? {
        var closest: (character: Character, distance: CGFloat)?
        for (key, frame) in keyFrames {
            guard let character = key.first else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let distance = hypot(point.x - center.x, point.y - center.y)
            if closest == nil || distance < closest!.distance {
                closest = (character, distance)
            }
        }
        guard let closest, closest.distance <= metrics.keyHeight * 1.2 else {
            return nil
        }
        return closest.character
    }
}

private struct SwipeTrail: View {
    let points: [CGPoint]

    var body: some View {
        if points.count > 1 {
            Path { path in
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(
                Color.accentColor.opacity(0.55),
                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

struct KeyFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct SymbolKeyboardLayer: View {
    enum Plane {
        case numbers
        case symbols
    }

    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge
    let metrics: KeyboardMetrics
    let plane: Plane

    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            CharacterRow(characters: plane == .numbers ? SymbolKeys.numbersTop : SymbolKeys.symbolsTop, model: model, metrics: metrics)
            CharacterRow(characters: plane == .numbers ? SymbolKeys.numbersMiddle : SymbolKeys.symbolsMiddle, model: model, metrics: metrics)
            HStack(spacing: metrics.keySpacing) {
                Button(plane == .numbers ? "#+=" : "123", action: model.toggleSymbolPlane)
                    .font(.callout)
                    .buttonStyle(
                        KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth, height: metrics.keyHeight)
                    )
                    .accessibilityLabel(plane == .numbers ? "Show more symbols" : "Show numbers")
                    .accessibilityIdentifier("keyboard.symbolPlane")

                CharacterRow(characters: SymbolKeys.bottom, model: model, metrics: metrics)

                DeleteKey(model: model, metrics: metrics)
            }
            KeyboardControlRow(model: model, controllerBridge: controllerBridge, metrics: metrics)
        }
    }
}

struct ShiftKey: View {
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    var body: some View {
        Button(action: model.toggleShift) {
            Image(systemName: shiftIcon)
                .frame(width: metrics.wideFunctionKeyWidth, height: metrics.keyHeight)
        }
        .buttonStyle(
            KeyboardFunctionButtonStyle(
                width: metrics.wideFunctionKeyWidth,
                height: metrics.keyHeight,
                isHighlighted: model.shiftState.isShifted
            )
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                model.activateCapsLock()
            }
        )
        .accessibilityLabel(shiftLabel)
        .accessibilityAddTraits(model.shiftState.isShifted ? .isSelected : [])
        .accessibilityIdentifier("keyboard.shift")
    }

    private var shiftIcon: String {
        switch model.shiftState {
        case .lowercase: "shift"
        case .uppercase: "shift.fill"
        case .capsLock: "capslock.fill"
        }
    }

    private var shiftLabel: String {
        switch model.shiftState {
        case .lowercase: "Shift off"
        case .uppercase: "Shift on"
        case .capsLock: "Caps lock on"
        }
    }
}

struct DeleteKey: View {
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "delete.left")
            .frame(width: metrics.wideFunctionKeyWidth, height: metrics.keyHeight)
            .foregroundStyle(Color.primary)
            .background(
                isPressed ? Color(uiColor: .systemGray2) : Color(uiColor: .systemGray3)
            )
            .clipShape(.rect(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        beginDeleting()
                    }
                    .onEnded { _ in
                        isPressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
            .accessibilityLabel("Delete")
            .accessibilityHint("Hold to keep deleting")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("keyboard.delete")
    }

    private func beginDeleting() {
        model.deleteBackward()
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            var interval = 110
            while !Task.isCancelled {
                model.deleteBackward()
                try? await Task.sleep(for: .milliseconds(interval))
                // Speed up gradually the longer the key is held.
                interval = max(45, interval - 6)
            }
        }
    }
}

private struct CharacterRow: View {
    let characters: [KeyboardCharacter]
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    var body: some View {
        HStack(spacing: metrics.keySpacing) {
            ForEach(characters) { character in
                KeyboardCharacterButton(character: character, model: model, metrics: metrics)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct KeyboardCharacterButton: View {
    let character: KeyboardCharacter
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    var body: some View {
        Button {
            model.insertCharacter(character.output)
        } label: {
            Text(displayedCharacter)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: metrics.keyHeight)
        }
        .buttonStyle(KeyboardKeyButtonStyle())
        .background {
            if model.layoutMode == .letters {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: KeyFramePreferenceKey.self,
                        value: [
                            character.output: proxy.frame(
                                in: .named("keyboard.swipeSpace")
                            ),
                        ]
                    )
                }
            }
        }
        .accessibilityLabel(character.accessibilityLabel)
        .accessibilityIdentifier("keyboard.key.\(character.id)")
    }

    private var displayedCharacter: String {
        guard model.layoutMode == .letters, model.shiftState.isShifted else {
            return character.output
        }
        return character.output.uppercased()
    }
}

struct KeyboardControlRow: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge
    let metrics: KeyboardMetrics

    var body: some View {
        HStack(spacing: metrics.keySpacing) {
            Button(model.layoutMode == .letters ? "123" : "ABC", action: model.toggleLayout)
                .font(.callout)
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth, height: metrics.keyHeight)
                )
                .accessibilityLabel(model.layoutMode == .letters ? "Show numbers and symbols" : "Show letters")
                .accessibilityIdentifier("keyboard.layout")

            if controllerBridge.needsInputModeSwitchKey {
                NextKeyboardButton(controllerBridge: controllerBridge)
                    .frame(width: metrics.letterKeyWidth * 1.1, height: metrics.keyHeight)
                    .accessibilityIdentifier("keyboard.globe")
            }

            Button {
                model.setLayout(.emoji)
            } label: {
                Image(systemName: "face.smiling")
                    .frame(width: metrics.letterKeyWidth * 1.1, height: metrics.keyHeight)
            }
            .buttonStyle(
                KeyboardFunctionButtonStyle(width: metrics.letterKeyWidth * 1.1, height: metrics.keyHeight)
            )
            .accessibilityLabel("Emoji")
            .accessibilityIdentifier("keyboard.emoji")

            Button(action: model.insertSpace) {
                Text("space")
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: metrics.keyHeight)
            }
            .buttonStyle(KeyboardKeyButtonStyle())
            .accessibilityIdentifier("keyboard.space")

            Button(action: model.insertReturn) {
                Image(systemName: "return")
                    .frame(width: metrics.wideFunctionKeyWidth * 1.3, height: metrics.keyHeight)
            }
            .buttonStyle(
                KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth * 1.3, height: metrics.keyHeight)
            )
            .accessibilityLabel("Return")
            .accessibilityIdentifier("keyboard.return")
        }
    }
}

struct KeyboardKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(configuration.isPressed ? Color(uiColor: .systemGray3) : Color(uiColor: .systemBackground))
            .clipShape(.rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.16), radius: 0.5, y: 1)
    }
}

struct KeyboardFunctionButtonStyle: ButtonStyle {
    let width: CGFloat
    var height: CGFloat = 42
    var isHighlighted = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .foregroundStyle(isHighlighted ? Color(uiColor: .systemBackground) : Color.primary)
            .background(
                isHighlighted
                    ? Color.primary.opacity(configuration.isPressed ? 0.6 : 0.85)
                    : configuration.isPressed ? Color(uiColor: .systemGray2) : Color(uiColor: .systemGray3)
            )
            .clipShape(.rect(cornerRadius: 6))
    }
}

struct KeyboardAccessoryButtonStyle: ButtonStyle {
    var isProminent = false
    var prominentColor = Color.accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .background(
                isProminent
                    ? prominentColor.opacity(configuration.isPressed ? 0.72 : 1)
                    : Color(uiColor: configuration.isPressed ? .systemGray3 : .systemBackground)
            )
            .clipShape(.rect(cornerRadius: 8))
    }
}

struct KeyboardCharacter: Identifiable, Equatable {
    let id: String
    let output: String
    let accessibilityLabel: String

    init(_ output: String, id: String? = nil, accessibilityLabel: String? = nil) {
        self.id = id ?? output
        self.output = output
        self.accessibilityLabel = accessibilityLabel ?? output
    }
}

private enum LetterKeys {
    static let top = "qwertyuiop".map { KeyboardCharacter(String($0), id: "letter-\($0)") }
    static let middle = "asdfghjkl".map { KeyboardCharacter(String($0), id: "letter-\($0)") }
    static let bottom = "zxcvbnm".map { KeyboardCharacter(String($0), id: "letter-\($0)") }
}

private enum SymbolKeys {
    static let numbersTop = "1234567890".map { KeyboardCharacter(String($0), id: "symbol-\($0)") }
    static let numbersMiddle = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
        .enumerated()
        .map { KeyboardCharacter($0.element, id: "symbol-middle-\($0.offset)") }
    static let symbolsTop = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
        .enumerated()
        .map { KeyboardCharacter($0.element, id: "shift-symbol-top-\($0.offset)") }
    static let symbolsMiddle = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
        .enumerated()
        .map { KeyboardCharacter($0.element, id: "shift-symbol-middle-\($0.offset)") }
    static let bottom = [".", ",", "?", "!", "'"]
        .enumerated()
        .map { KeyboardCharacter($0.element, id: "symbol-bottom-\($0.offset)") }
}
