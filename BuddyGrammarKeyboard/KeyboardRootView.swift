import BuddyGrammarKit
import Observation
import SwiftUI

struct KeyboardMetrics: Equatable {
    let width: CGFloat
    let bodyHeight: CGFloat
    let outerPadding: CGFloat

    var keySpacing: CGFloat { width > 600 ? 7 : 5 }
    var rowSpacing: CGFloat { width > 600 ? 8 : 7 }
    var horizontalPadding: CGFloat { 4 }
    var suggestionBarHeight: CGFloat { 44 }
    var keyHeight: CGFloat {
        min(58, max(30, (bodyHeight - 3 * rowSpacing) / 4))
    }
    var letterKeyWidth: CGFloat {
        max(20, (width - 2 * horizontalPadding - 9 * keySpacing) / 10)
    }
    var wideFunctionKeyWidth: CGFloat { min(64, letterKeyWidth * 1.35) }

    init(size: CGSize) {
        let maximumThumbReachWidth: CGFloat = size.width >= 760 ? 720 : size.width
        width = max(280, min(size.width, maximumThumbReachWidth))
        outerPadding = max(4, (size.width - width) / 2)
        bodyHeight = max(120, size.height - 44 - 14)
    }

    init(width: CGFloat, bodyHeight: CGFloat) {
        self.width = width
        self.bodyHeight = bodyHeight
        outerPadding = 4
    }
}

private let keyboardPointerCoordinateSpace = "keyboard.pointer"

struct KeyboardRootView: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge

    @State private var interaction = KeyboardPointerInteraction()
    @State private var isBuddyDrawerPresented = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = KeyboardMetrics(size: proxy.size)

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    KeyboardSuggestionBar(
                        model: model,
                        isBuddyDrawerPresented: $isBuddyDrawerPresented
                    )
                    .frame(height: metrics.suggestionBarHeight)

                    keyboardBody(metrics: metrics)
                        .coordinateSpace(.named(keyboardPointerCoordinateSpace))
                        .overlay {
                            if model.layoutMode == .letters {
                                SwipeTrail(points: interaction.swipePoints)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(maxHeight: .infinity)
                }

                if let proposal = model.correctionProposal {
                    BuddyCorrectionProposalCard(
                        proposal: proposal,
                        scope: model.correctionProposalScope,
                        accept: model.acceptCorrectionProposal,
                        dismiss: model.dismissCorrectionProposal
                    )
                    .frame(maxWidth: min(metrics.width - 8, 620))
                    .padding(.top, metrics.suggestionBarHeight + 8)
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(30)
                } else if isBuddyDrawerPresented {
                    BuddyDrawer(
                        model: model,
                        dismiss: { isBuddyDrawerPresented = false }
                    )
                    .frame(maxWidth: min(metrics.width - 8, 620))
                    .padding(.top, metrics.suggestionBarHeight + 8)
                    .padding(.trailing, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
                }
            }
            .frame(width: metrics.width)
            .padding(.leading, metrics.outerPadding)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .background(Color(uiColor: .systemGray5))
        .sensoryFeedback(.impact(weight: .light), trigger: interaction.keyFeedbackCount)
        .sensoryFeedback(.selection, trigger: interaction.selectionFeedbackCount)
        .onAppear {
            interaction.connect(
                model: model,
                configuration: model.keyboardInteractionConfiguration
            )
        }
        .onChange(of: model.keyboardInteractionConfiguration) { _, configuration in
            interaction.updateConfiguration(configuration)
        }
        .onChange(of: model.layoutMode) { _, _ in
            interaction.cancel()
            isBuddyDrawerPresented = false
        }
        .animation(.snappy, value: isBuddyDrawerPresented)
    }

    @ViewBuilder
    private func keyboardBody(metrics: KeyboardMetrics) -> some View {
        switch model.layoutMode {
        case .letters:
            LetterKeyboardLayer(
                model: model,
                controllerBridge: controllerBridge,
                metrics: metrics,
                interaction: interaction
            )
        case .numbers where model.usesNumericFieldLayout:
            NumericFieldKeyboardLayer(
                model: model,
                controllerBridge: controllerBridge,
                metrics: metrics,
                interaction: interaction
            )
        case .numbers:
            SymbolKeyboardLayer(
                model: model,
                controllerBridge: controllerBridge,
                metrics: metrics,
                interaction: interaction,
                plane: .numbers
            )
        case .symbols:
            SymbolKeyboardLayer(
                model: model,
                controllerBridge: controllerBridge,
                metrics: metrics,
                interaction: interaction,
                plane: .symbols
            )
        case .latex:
            LatexKeyboardLayer(model: model, metrics: metrics)
        case .emoji:
            EmojiKeyboardLayer(model: model, metrics: metrics)
        case .handwriting:
            HandwritingKeyboardLayer(model: model, metrics: metrics)
        }
    }
}

private enum SuggestionSlot: Int, CaseIterable, Identifiable {
    case first
    case second
    case third

    var id: Int { rawValue }
}

private struct KeyboardSuggestionBar: View {
    let model: KeyboardModel
    @Binding var isBuddyDrawerPresented: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if model.canUndoCorrection {
                    Button(action: model.undoLastCorrection) {
                        Label("Undo Buddy change", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(KeyboardAccessoryButtonStyle())
                    .accessibilityIdentifier("keyboard.undo")
                    .accessibilityHint("Restores the text from before the Buddy change")
                } else if let original = model.automaticCorrectionOriginalText {
                    Button(action: model.undoAutomaticCorrection) {
                        Label("Undo to \(original)", systemImage: "arrow.uturn.backward.circle")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(KeyboardAccessoryButtonStyle())
                    .accessibilityIdentifier("keyboard.autocorrection.undo")
                } else if model.isStatusPresented, model.status != .ready {
                    StatusIndicator(status: model.status)
                        .frame(maxWidth: .infinity)
                } else {
                    StableSuggestionSlots(model: model)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                isBuddyDrawerPresented.toggle()
            } label: {
                Label("Buddy", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 32)
            }
            .buttonStyle(
                KeyboardAccessoryButtonStyle(isProminent: isBuddyDrawerPresented)
            )
            .accessibilityIdentifier("keyboard.buddy")
            .accessibilityLabel(
                isBuddyDrawerPresented ? "Close Buddy tools" : "Open Buddy tools"
            )
        }
        .animation(.snappy, value: model.canUndoCorrection)
        .animation(.snappy, value: model.automaticCorrectionOriginalText)
    }
}

private struct StableSuggestionSlots: View {
    let model: KeyboardModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(SuggestionSlot.allCases) { slot in
                suggestionSlot(at: slot.rawValue)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
        }
    }

    @ViewBuilder
    private func suggestionSlot(at index: Int) -> some View {
        if model.suggestions.indices.contains(index) {
            let suggestion = model.suggestions[index]
            Button {
                model.playInputClick()
                model.insertSuggestion(suggestion)
            } label: {
                HStack(spacing: 4) {
                    if suggestion.kind == .correction {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                            .accessibilityHidden(true)
                    }
                    Text(suggestion.display)
                        .font(
                            .subheadline.weight(
                                suggestion.kind == .correction ? .semibold : .regular
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(KeyboardAccessoryButtonStyle())
            .accessibilityIdentifier("keyboard.suggestion.\(suggestion.id)")
            .accessibilityLabel(
                suggestion.kind == .correction
                    ? "Correct to \(suggestion.display)"
                    : "Insert \(suggestion.display)"
            )
            .contextMenu {
                if model.allowsCorrectionPreferenceActions,
                   suggestion.kind == .correction,
                   let original = suggestion.originalText {
                    Button("Add “\(original)” to dictionary", systemImage: "text.badge.plus") {
                        model.addToDictionary(from: suggestion)
                    }
                    Button(
                        "Never suggest this correction",
                        systemImage: "nosign"
                    ) {
                        model.neverSuggestCorrection(suggestion)
                    }
                }
            }
            .accessibilityActions {
                if model.allowsCorrectionPreferenceActions,
                   suggestion.kind == .correction,
                   let original = suggestion.originalText {
                    Button("Add \(original) to dictionary") {
                        model.addToDictionary(from: suggestion)
                    }
                    Button(
                        "Never suggest \(suggestion.display) for \(original)"
                    ) {
                        model.neverSuggestCorrection(suggestion)
                    }
                }
            }
        } else {
            Color.clear
                .contentShape(.rect)
                .accessibilityHidden(true)
        }
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
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(status.isError ? Color.orange : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keyboard.status")
    }

    private var iconName: String {
        switch status {
        case .correcting:
            "hourglass"
        case .corrected, .correctionUndone, .automaticCorrectionReverted,
             .transcriptInserted, .addedToDictionary:
            "checkmark.circle.fill"
        case .correctionProposalReady:
            "doc.text.magnifyingglass"
        case .correctionProposalDismissed:
            "xmark.circle"
        case .swipeAbstained:
            "hand.raised"
        case .correctionSuggestionSuppressed:
            "nosign"
        case .appleDictationGuidance:
            "keyboard"
        case .settingsGuidance:
            "gearshape"
        case .ready:
            "sparkles"
        case .fullAccessRequired:
            "lock"
        case .cloudConsentRequired:
            "hand.raised"
        case .noText, .noPendingTranscript, .staleContext, .capabilityDenied, .error:
            "exclamationmark.triangle"
        }
    }
}

private struct BuddyCorrectionProposalCard: View {
    let proposal: ReviewableCorrectionProposal
    let scope: KeyboardCorrectionScope?
    let accept: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Label(proposal.intent.title, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                Text("Cloud")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.14))
                    .clipShape(.capsule)
                Text(scope?.label ?? "Text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Original")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                originalDiff
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Proposed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                proposedDiff
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Original: \(proposal.originalText). Proposed: \(proposal.proposedText)"
            )

            HStack(spacing: 8) {
                Button("Dismiss", action: dismiss)
                    .buttonStyle(KeyboardAccessoryButtonStyle())
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .accessibilityIdentifier("keyboard.proposal.dismiss")

                Button("Accept", action: accept)
                    .buttonStyle(KeyboardAccessoryButtonStyle(isProminent: true))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .disabled(!proposal.hasChanges)
                    .accessibilityIdentifier("keyboard.proposal.accept")
                    .accessibilityHint(
                        "Applies this entire Buddy change and makes it undoable"
                    )
            }
        }
        .padding(10)
        .background(Color(uiColor: .systemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.24), radius: 9, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard.proposal")
    }

    private var originalDiff: Text {
        let change = proposal.change
        return Text(change.commonPrefix)
            + Text(change.originalChangedText)
                .foregroundStyle(.red)
                .strikethrough()
            + Text(change.commonSuffix)
    }

    private var proposedDiff: Text {
        let change = proposal.change
        return Text(change.commonPrefix)
            + Text(change.proposedChangedText)
                .foregroundStyle(.green)
                .bold()
            + Text(change.commonSuffix)
    }
}

private struct BuddyDrawer: View {
    let model: KeyboardModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buddy writing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(BuddyRewriteIntent.allCases) { intent in
                        drawerButton(
                            intent.title,
                            icon: intent == .fix ? "checkmark.seal" : "textformat"
                        ) {
                            model.correctCurrentText(intent: intent)
                        }
                        .disabled(
                            model.status == .correcting
                                || !model.editorCapabilities.cloudCorrection.isAllowed
                        )
                        .accessibilityIdentifier("keyboard.buddy.\(intent.rawValue)")
                        .accessibilityHint(
                            model.status == .correcting
                                ? "Wait for the current Buddy request to finish."
                                : capabilityHint(
                                    model.editorCapabilities.cloudCorrection,
                                    allowed: "Creates a reviewable \(intent.title.lowercased()) proposal."
                                )
                        )
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    drawerButton(
                        "Language \(model.keyboardLanguageButtonLabel)",
                        icon: "character.bubble"
                    ) {
                        model.playInputClick()
                        model.toggleKeyboardLanguage()
                    }
                    .accessibilityIdentifier("keyboard.language")
                    .accessibilityLabel(model.keyboardLanguageAccessibilityLabel)

                    drawerButton("Delete word", icon: "delete.backward") {
                        model.playInputClick()
                        model.deleteWordBackward()
                    }
                    .accessibilityIdentifier("keyboard.deleteWord")
                    .accessibilityHint(
                        "Deletes one whitespace run, word run, or punctuation character."
                    )

                    drawerButton("Apple Dictation", icon: "keyboard") {
                        model.showAppleDictationGuidance()
                    }
                    .accessibilityIdentifier("keyboard.dictationGuide")
                    .accessibilityHint(
                        "Explains how to use Apple Dictation from the system keyboard"
                    )

                    drawerButton("Handwriting", icon: "pencil.and.scribble") {
                        model.setLayout(.handwriting)
                    }
                    .accessibilityIdentifier("keyboard.handwriting")
                    .disabled(!model.editorCapabilities.localHandwriting.isAllowed)
                    .accessibilityHint(
                        handwritingHint(
                            local: model.editorCapabilities.localHandwriting,
                            cloud: model.editorCapabilities.cloudHandwriting
                        )
                    )

                    drawerButton("LaTeX", icon: "x.squareroot") {
                        model.setLayout(.latex)
                    }
                    .accessibilityIdentifier("keyboard.latex")
                    .disabled(!model.editorCapabilities.literalTools.isAllowed)
                    .accessibilityHint(
                        capabilityHint(
                            model.editorCapabilities.literalTools,
                            allowed: "Inserts literal LaTeX without language processing."
                        )
                    )

                    drawerButton("Saved transcript", icon: "tray.and.arrow.down") {
                        model.insertPendingTranscript()
                    }
                    .accessibilityIdentifier("keyboard.savedTranscript")
                    .disabled(!model.editorCapabilities.transcriptInsertion.isAllowed)
                    .accessibilityHint(
                        capabilityHint(
                            model.editorCapabilities.transcriptInsertion,
                            allowed: "Inserts the transcript visibly saved by BuddyGrammar."
                        )
                    )

                    drawerButton("Settings", icon: "gearshape") {
                        model.showSettingsGuidance()
                    }
                    .accessibilityIdentifier("keyboard.settingsGuide")
                }
            }
        }
        .padding(10)
        .background(Color(uiColor: .systemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }

    private func drawerButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .frame(height: 32)
        }
        .buttonStyle(KeyboardAccessoryButtonStyle())
    }

    private func capabilityHint(
        _ access: EditorFeatureAccess,
        allowed: String
    ) -> String {
        guard let denial = access.denialReason else { return allowed }
        return KeyboardStatus.capabilityDenied(denial).message
    }

    private func handwritingHint(
        local: EditorFeatureAccess,
        cloud: EditorFeatureAccess
    ) -> String {
        if let denial = local.denialReason {
            return KeyboardStatus.capabilityDenied(denial).message
        }
        guard let denial = cloud.denialReason else {
            return "Recognizes handwriting on device and may use the consented AI fallback."
        }
        return "On-device handwriting remains available. \(KeyboardStatus.capabilityDenied(denial).message) AI fallback stays off."
    }
}

private struct LetterKeyboardLayer: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge
    let metrics: KeyboardMetrics
    let interaction: KeyboardPointerInteraction

    @State private var keyFrames: [String: CGRect] = [:]

    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            RoutedCharacterRow(
                characters: model.keyboardLetterRows[safe: 0] ?? [],
                model: model,
                metrics: metrics,
                interaction: interaction,
                allowsSwipe: model.editorCapabilities.swipeTyping.isAllowed,
                recordsLetterFrames: true
            )
            RoutedCharacterRow(
                characters: model.keyboardLetterRows[safe: 1] ?? [],
                model: model,
                metrics: metrics,
                interaction: interaction,
                allowsSwipe: model.editorCapabilities.swipeTyping.isAllowed,
                recordsLetterFrames: true
            )
            .padding(.horizontal, metrics.letterKeyWidth / 2)

            HStack(spacing: metrics.keySpacing) {
                ShiftKey(model: model, metrics: metrics)
                RoutedCharacterRow(
                    characters: model.keyboardLetterRows[safe: 2] ?? [],
                    model: model,
                    metrics: metrics,
                    interaction: interaction,
                    allowsSwipe: model.editorCapabilities.swipeTyping.isAllowed,
                    recordsLetterFrames: true
                )
                DeleteKey(model: model, metrics: metrics, interaction: interaction)
            }

            KeyboardControlRow(
                model: model,
                controllerBridge: controllerBridge,
                metrics: metrics,
                interaction: interaction
            )
        }
        .onPreferenceChange(KeyFramePreferenceKey.self) { frames in
            keyFrames = frames
            interaction.updateKeyFrames(frames)
        }
        .onDisappear {
            interaction.cancel()
            keyFrames = [:]
        }
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
    let interaction: KeyboardPointerInteraction
    let plane: Plane

    private var rows: [[String]] {
        plane == .numbers ? model.keyboardNumberRows : model.keyboardSymbolRows
    }

    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            RoutedCharacterRow(
                characters: rows[safe: 0] ?? [],
                model: model,
                metrics: metrics,
                interaction: interaction
            )
            RoutedCharacterRow(
                characters: rows[safe: 1] ?? [],
                model: model,
                metrics: metrics,
                interaction: interaction
            )

            HStack(spacing: metrics.keySpacing) {
                Button(plane == .numbers ? "#+=" : "123") {
                    model.playInputClick()
                    model.toggleSymbolPlane()
                }
                    .font(.callout)
                    .buttonStyle(
                        KeyboardFunctionButtonStyle(
                            width: metrics.wideFunctionKeyWidth,
                            height: metrics.keyHeight
                        )
                    )
                    .accessibilityLabel(
                        plane == .numbers ? "Show more symbols" : "Show numbers"
                    )
                    .accessibilityIdentifier("keyboard.symbolPlane")

                RoutedCharacterRow(
                    characters: [".", ",", "?", "!", "'"],
                    model: model,
                    metrics: metrics,
                    interaction: interaction
                )

                DeleteKey(model: model, metrics: metrics, interaction: interaction)
            }

            KeyboardControlRow(
                model: model,
                controllerBridge: controllerBridge,
                metrics: metrics,
                interaction: interaction
            )
        }
    }
}

private struct NumericFieldKeyboardLayer: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge
    let metrics: KeyboardMetrics
    let interaction: KeyboardPointerInteraction

    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            ForEach(model.keyboardNumericRows.prefix(3), id: \.self) { row in
                RoutedCharacterRow(
                    characters: row,
                    model: model,
                    metrics: metrics,
                    interaction: interaction
                )
            }

            HStack(spacing: metrics.keySpacing) {
                Button("ABC") {
                    model.playInputClick()
                    model.setLayout(.letters)
                }
                .font(.caption.weight(.medium))
                .buttonStyle(
                    KeyboardFunctionButtonStyle(
                        width: metrics.wideFunctionKeyWidth,
                        height: metrics.keyHeight
                    )
                )
                .accessibilityLabel("Show letters")
                .accessibilityIdentifier("keyboard.layout")

                if controllerBridge.needsInputModeSwitchKey {
                    NextKeyboardButton(controllerBridge: controllerBridge)
                        .frame(width: 34, height: metrics.keyHeight)
                        .accessibilityIdentifier("keyboard.globe")
                }

                ForEach(model.keyboardInlineKeys, id: \.id) { key in
                    RoutedCharacterKey(
                        output: key.output,
                        display: key.label,
                        accessibilityLabel: key.label,
                        model: model,
                        metrics: metrics,
                        interaction: interaction
                    )
                    .frame(minWidth: 30)
                }

                RoutedCharacterKey(
                    output: model.keyboardNumericRows.last?.first ?? "0",
                    model: model,
                    metrics: metrics,
                    interaction: interaction
                )

                DeleteKey(model: model, metrics: metrics, interaction: interaction)
                ReturnKey(model: model, metrics: metrics)
            }
        }
    }
}

struct ShiftKey: View {
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    var body: some View {
        Button {
            model.playInputClick()
            model.toggleShift()
        } label: {
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
    let interaction: KeyboardPointerInteraction

    @State private var gestureID: UUID?

    var body: some View {
        Image(systemName: "delete.left")
            .frame(width: metrics.wideFunctionKeyWidth, height: metrics.keyHeight)
            .foregroundStyle(Color.primary)
            .background(
                interaction.isPressed(.delete)
                    ? Color(uiColor: .systemGray2)
                    : Color(uiColor: .systemGray3)
            )
            .clipShape(.rect(cornerRadius: 6))
            .contentShape(.rect)
            .gesture(pointerGesture)
            .onDisappear(perform: cancelGesture)
            .accessibilityLabel("Delete")
            .accessibilityHint(
                "Hold to repeatedly delete characters. Use Delete word to remove a word"
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                model.playInputClick()
                model.deleteBackward()
            }
            .accessibilityAction(named: Text("Delete word")) {
                model.playInputClick()
                model.deleteWordBackward()
            }
            .accessibilityIdentifier("keyboard.delete")
    }

    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(keyboardPointerCoordinateSpace))
            .onChanged { value in
                guard gestureID == nil else { return }
                let token = UUID()
                gestureID = token
                interaction.press(
                    target: .delete,
                    at: value.startLocation,
                    gestureID: token
                )
            }
            .onEnded { value in
                guard let token = gestureID else { return }
                interaction.release(at: value.location, gestureID: token)
                gestureID = nil
            }
    }

    private func cancelGesture() {
        guard let token = gestureID else { return }
        interaction.cancel(gestureID: token)
        gestureID = nil
    }
}

private struct RoutedCharacterRow: View {
    let characters: [String]
    let model: KeyboardModel
    let metrics: KeyboardMetrics
    let interaction: KeyboardPointerInteraction
    var allowsSwipe = false
    var recordsLetterFrames = false

    var body: some View {
        HStack(spacing: metrics.keySpacing) {
            ForEach(characters, id: \.self) { character in
                RoutedCharacterKey(
                    output: character,
                    id: character,
                    model: model,
                    metrics: metrics,
                    interaction: interaction,
                    allowsSwipe: allowsSwipe,
                    recordsLetterFrame: recordsLetterFrames
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RoutedCharacterKey: View {
    let output: String
    var id: String?
    var display: String?
    var accessibilityLabel: String?
    let model: KeyboardModel
    let metrics: KeyboardMetrics
    let interaction: KeyboardPointerInteraction
    var allowsSwipe = false
    var recordsLetterFrame = false

    @State private var gestureID: UUID?

    private var alternates: [String] {
        model.alternates(for: output)
    }

    private var target: KeyboardInteractionTarget {
        .key(output, alternates: alternates, allowsSwipe: allowsSwipe)
    }

    var body: some View {
        Text(displayedOutput)
            .font(.title3)
            .frame(maxWidth: .infinity, minHeight: metrics.keyHeight)
            .foregroundStyle(Color.primary)
            .background(
                interaction.isPressed(target)
                    ? Color(uiColor: .systemGray3)
                    : Color(uiColor: .systemBackground)
            )
            .clipShape(.rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.16), radius: 0.5, y: 1)
            .contentShape(.rect)
            .background {
                if recordsLetterFrame {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: KeyFramePreferenceKey.self,
                            value: [
                                output.lowercased(): proxy.frame(
                                    in: .named(keyboardPointerCoordinateSpace)
                                ),
                            ]
                        )
                    }
                }
            }
            .overlay(alignment: .top) {
                keyPopup
            }
            .zIndex(interaction.isPressed(target) ? 5 : 0)
            .gesture(pointerGesture)
            .onDisappear(perform: cancelGesture)
            .accessibilityLabel(accessibilityLabel ?? output)
            .accessibilityHint(alternates.isEmpty ? "" : "Hold for accented characters")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                model.playInputClick()
                model.insertLiteralCharacter(output)
            }
            .accessibilityActions {
                ForEach(alternates, id: \.self) { alternate in
                    Button("Insert \(alternate)") {
                        model.playInputClick()
                        model.insertLiteralCharacter(alternate)
                    }
                }
            }
            .accessibilityIdentifier("keyboard.key.\(id ?? output)")
    }

    @ViewBuilder
    private var keyPopup: some View {
        if interaction.isPressed(target), !interaction.alternateOptions.isEmpty {
            HStack(spacing: 3) {
                ForEach(interaction.alternateOptions, id: \.self) { alternate in
                    Text(model.shiftState.isShifted ? alternate.uppercased() : alternate)
                        .font(.title3)
                        .frame(width: 34, height: 42)
                        .background(
                            interaction.alternateOptions.firstIndex(of: alternate)
                                == interaction.selectedAlternateIndex
                                ? Color.accentColor
                                : Color(uiColor: .systemBackground)
                        )
                        .foregroundStyle(
                            interaction.alternateOptions.firstIndex(of: alternate)
                                == interaction.selectedAlternateIndex
                                ? Color.white
                                : Color.primary
                        )
                }
            }
            .padding(4)
            .background(Color(uiColor: .systemGray4))
            .clipShape(.rect(cornerRadius: 8))
            .shadow(radius: 3, y: 1)
            .offset(y: -52)
        } else if interaction.isPressed(target), interaction.previewText != nil {
            Text(displayedOutput)
                .font(.title2)
                .frame(width: max(42, metrics.letterKeyWidth * 1.15), height: 52)
                .background(Color(uiColor: .systemBackground))
                .clipShape(.rect(cornerRadius: 8))
                .shadow(radius: 3, y: 1)
                .offset(y: -58)
        }
    }

    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(keyboardPointerCoordinateSpace))
            .onChanged { value in
                if let token = gestureID {
                    if allowsSwipe || !alternates.isEmpty {
                        interaction.move(to: value.location, gestureID: token)
                    }
                } else {
                    let token = UUID()
                    gestureID = token
                    interaction.press(
                        target: target,
                        at: value.startLocation,
                        gestureID: token
                    )
                }
            }
            .onEnded { value in
                guard let token = gestureID else { return }
                interaction.release(at: value.location, gestureID: token)
                gestureID = nil
            }
    }

    private func cancelGesture() {
        guard let token = gestureID else { return }
        interaction.cancel(gestureID: token)
        gestureID = nil
    }

    private var displayedOutput: String {
        let literal = display ?? output
        guard model.layoutMode == .letters, model.shiftState.isShifted else {
            return literal
        }
        return literal.uppercased()
    }
}

struct KeyboardControlRow: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge
    let metrics: KeyboardMetrics
    let interaction: KeyboardPointerInteraction

    private var hidesSpaceBar: Bool {
        guard let fieldKind = model.keyboardPresentation?.fieldKind else { return false }
        return fieldKind == .email || fieldKind == .url
    }

    var body: some View {
        HStack(spacing: metrics.keySpacing) {
            Button(model.layoutMode == .letters ? "123" : "ABC") {
                model.playInputClick()
                model.toggleLayout()
            }
                .font(.caption.weight(.medium))
                .buttonStyle(
                    KeyboardFunctionButtonStyle(
                        width: max(36, metrics.wideFunctionKeyWidth * 0.82),
                        height: metrics.keyHeight
                    )
                )
                .accessibilityLabel(
                    model.layoutMode == .letters
                        ? "Show numbers and symbols"
                        : "Show letters"
                )
                .accessibilityIdentifier("keyboard.layout")

            if controllerBridge.needsInputModeSwitchKey {
                NextKeyboardButton(controllerBridge: controllerBridge)
                    .frame(width: 30, height: metrics.keyHeight)
                    .accessibilityIdentifier("keyboard.globe")
            }

            if model.keyboardInlineKeys.isEmpty {
                Button {
                    model.playInputClick()
                    model.setLayout(.emoji)
                } label: {
                    Image(systemName: "face.smiling")
                        .frame(width: 30, height: metrics.keyHeight)
                }
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: 30, height: metrics.keyHeight)
                )
                .accessibilityLabel("Emoji")
                .accessibilityIdentifier("keyboard.emoji")
            }

            ForEach(model.keyboardInlineKeys, id: \.id) { key in
                RoutedCharacterKey(
                    output: key.output,
                    display: key.label,
                    accessibilityLabel: key.label,
                    model: model,
                    metrics: metrics,
                    interaction: interaction
                )
                .frame(width: key.output.count > 2 ? 42 : 28)
            }

            if !hidesSpaceBar {
                SpaceKey(model: model, metrics: metrics, interaction: interaction)
            }

            ReturnKey(model: model, metrics: metrics)
        }
    }
}

private struct SpaceKey: View {
    let model: KeyboardModel
    let metrics: KeyboardMetrics
    let interaction: KeyboardPointerInteraction

    @State private var gestureID: UUID?

    var body: some View {
        Text(interaction.isCursorMode ? "↔︎" : model.keyboardSpaceLabel)
            .font(.callout)
            .frame(maxWidth: .infinity, minHeight: metrics.keyHeight)
            .foregroundStyle(Color.primary)
            .background(
                interaction.isPressed(.space)
                    ? Color(uiColor: .systemGray3)
                    : Color(uiColor: .systemBackground)
            )
            .clipShape(.rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.16), radius: 0.5, y: 1)
            .contentShape(.rect)
            .gesture(pointerGesture)
            .onDisappear(perform: cancelGesture)
            .accessibilityLabel(model.keyboardSpaceLabel)
            .accessibilityHint("Hold, then slide to move the cursor")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                model.playInputClick()
                model.insertSpace()
            }
            .accessibilityAction(named: Text("Move cursor left")) {
                model.moveCursor(byCharacterOffset: -1)
            }
            .accessibilityAction(named: Text("Move cursor right")) {
                model.moveCursor(byCharacterOffset: 1)
            }
            .accessibilityIdentifier("keyboard.space")
    }

    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(keyboardPointerCoordinateSpace))
            .onChanged { value in
                if let token = gestureID {
                    interaction.move(to: value.location, gestureID: token)
                } else {
                    let token = UUID()
                    gestureID = token
                    interaction.press(
                        target: .space,
                        at: value.startLocation,
                        gestureID: token
                    )
                }
            }
            .onEnded { value in
                guard let token = gestureID else { return }
                interaction.release(at: value.location, gestureID: token)
                gestureID = nil
            }
    }

    private func cancelGesture() {
        guard let token = gestureID else { return }
        interaction.cancel(gestureID: token)
        gestureID = nil
    }
}

private struct ReturnKey: View {
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    var body: some View {
        Button {
            model.playInputClick()
            model.insertReturn()
        } label: {
            Text(model.keyboardReturnLabel)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(
                    width: max(48, metrics.wideFunctionKeyWidth * 1.08),
                    height: metrics.keyHeight
                )
        }
        .buttonStyle(
            KeyboardFunctionButtonStyle(
                width: max(48, metrics.wideFunctionKeyWidth * 1.08),
                height: metrics.keyHeight
            )
        )
        .accessibilityLabel(model.keyboardReturnLabel)
        .accessibilityIdentifier("keyboard.return")
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

@MainActor
@Observable
final class KeyboardPointerInteraction {
    private static let maximumLiveSwipeSamples = 256

    private(set) var pressedTarget: KeyboardInteractionTarget?
    private(set) var previewText: String?
    private(set) var alternateOptions: [String] = []
    private(set) var selectedAlternateIndex = 0
    private(set) var swipePoints: [CGPoint] = []
    private(set) var keyFeedbackCount = 0
    private(set) var selectionFeedbackCount = 0
    private(set) var isCursorMode = false

    @ObservationIgnored private weak var model: KeyboardModel?
    @ObservationIgnored private var router = KeyboardInteractionRouter()
    @ObservationIgnored private var pointerOwner = SinglePointerInteractionOwner<UUID>()
    @ObservationIgnored private var deadlineTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var keyFrames: [String: CGRect] = [:]
    @ObservationIgnored private var activeLiteral: String?
    @ObservationIgnored private var activeOrigin: CGPoint?
    @ObservationIgnored private var activeDownTime: TimeInterval?
    @ObservationIgnored private var feedbackLatencyToken: KeyboardLatencyToken?
    @ObservationIgnored private var commitLatencyToken: KeyboardLatencyToken?
    @ObservationIgnored private var swipeSampleBuffer = BoundedSwipePathBuffer(
        capacity: maximumLiveSwipeSamples
    )
    @ObservationIgnored private var pendingPointerSamples: [(CGPoint, TimeInterval)] = []

    func connect(
        model: KeyboardModel,
        configuration: KeyboardInteractionRouter.Configuration
    ) {
        self.model = model
        updateConfiguration(configuration)
    }

    func updateConfiguration(_ configuration: KeyboardInteractionRouter.Configuration) {
        cancel()
        router = KeyboardInteractionRouter(configuration: configuration)
    }

    func updateKeyFrames(_ frames: [String: CGRect]) {
        keyFrames = frames
    }

    func isPressed(_ target: KeyboardInteractionTarget) -> Bool {
        pressedTarget == target
    }

    @discardableResult
    func press(
        target: KeyboardInteractionTarget,
        at point: CGPoint,
        gestureID: UUID
    ) -> Bool {
        guard pointerOwner.acquire(gestureID) else { return false }
        cancelDeadlines()
        cancelActiveLatencyMeasurements()
        feedbackLatencyToken = KeyboardLatencyRecorder.production.begin(.keyDownToFeedback)
        commitLatencyToken = KeyboardLatencyRecorder.production.begin(.keyDownToCommit)
        let eventTime = ProcessInfo.processInfo.systemUptime
        activeDownTime = eventTime
        pendingPointerSamples = [(point, eventTime)]
        if case .key(let literal, _, _) = target {
            activeLiteral = literal
            activeOrigin = point
        } else {
            activeLiteral = nil
            activeOrigin = point
        }
        apply(
            router.handle(
                .press(
                    target: target,
                    at: InteractionPoint(point),
                    time: eventTime
                )
            ),
            eventTime: eventTime
        )
        return true
    }

    @discardableResult
    func move(to point: CGPoint, gestureID: UUID) -> Bool {
        guard pointerOwner.owns(gestureID) else { return false }
        let eventTime = ProcessInfo.processInfo.systemUptime
        recordPointerSample(point, timestamp: eventTime)
        apply(
            router.handle(
                .move(
                    to: InteractionPoint(point),
                    time: eventTime
                )
            ),
            eventTime: eventTime
        )
        return true
    }

    @discardableResult
    func release(at point: CGPoint, gestureID: UUID) -> Bool {
        guard pointerOwner.owns(gestureID) else { return false }
        defer { pointerOwner.release(gestureID) }
        cancelDeadlines()
        let eventTime = ProcessInfo.processInfo.systemUptime
        recordPointerSample(point, timestamp: eventTime)
        apply(
            router.handle(
                .release(
                    at: InteractionPoint(point),
                    time: eventTime
                )
            ),
            eventTime: eventTime
        )
        cancelActiveLatencyMeasurements()
        activeLiteral = nil
        activeOrigin = nil
        activeDownTime = nil
        pendingPointerSamples = []
        isCursorMode = false
        return true
    }

    @discardableResult
    func cancel(gestureID: UUID) -> Bool {
        guard pointerOwner.owns(gestureID) else { return false }
        pointerOwner.release(gestureID)
        cancelRouterInteraction()
        return true
    }

    /// Force-cancels the active interaction during adapter teardown or a
    /// keyboard layout transition, regardless of which key view owns it.
    func cancel() {
        pointerOwner.reset()
        cancelRouterInteraction()
    }

    private func cancelRouterInteraction() {
        cancelDeadlines()
        apply(
            router.handle(.cancel),
            eventTime: ProcessInfo.processInfo.systemUptime
        )
        cancelActiveLatencyMeasurements()
        activeLiteral = nil
        activeOrigin = nil
        activeDownTime = nil
        swipePoints = []
        swipeSampleBuffer.removeAll()
        pendingPointerSamples = []
        isCursorMode = false
    }

    private func apply(
        _ effects: [KeyboardInteractionEffect],
        eventTime: TimeInterval
    ) {
        for effect in effects {
            switch effect {
            case .pressed(let target):
                pressedTarget = target
                if target == nil {
                    isCursorMode = false
                }
            case .preview(let text):
                previewText = text
            case .schedule(let deadline):
                schedule(deadline)
            case .showAlternates(let options, let index):
                alternateOptions = options
                selectedAlternateIndex = index
            case .hideAlternates:
                alternateOptions = []
                selectedAlternateIndex = 0
            case .commitText(let text):
                commit(text)
                finishCommitLatencyMeasurement()
            case .deleteBackward:
                model?.deleteBackward()
                finishCommitLatencyMeasurement()
            case .deleteWord:
                model?.deleteWordBackward()
                finishCommitLatencyMeasurement()
            case .moveCursor(let offset):
                isCursorMode = true
                model?.moveCursor(byCharacterOffset: offset)
            case .swipeBegan(let point):
                cancelActiveLatencyMeasurements()
                beginSwipe(at: point.cgPoint, eventTime: eventTime)
            case .swipeMoved(let point):
                appendSwipeSample(point.cgPoint, timestamp: eventTime)
            case .swipeEnded(let point):
                appendSwipeSample(point.cgPoint, timestamp: eventTime)
                commitSwipe()
            case .feedback(.key):
                model?.playInputClick()
                keyFeedbackCount &+= 1
                finishFeedbackLatencyMeasurement()
            case .feedback(.selection):
                if pressedTarget == .space {
                    isCursorMode = true
                }
                selectionFeedbackCount &+= 1
                finishFeedbackLatencyMeasurement()
            }
        }
    }

    private func finishFeedbackLatencyMeasurement() {
        guard let token = feedbackLatencyToken else { return }
        feedbackLatencyToken = nil
        KeyboardLatencyRecorder.production.finish(token)
    }

    private func finishCommitLatencyMeasurement() {
        guard let token = commitLatencyToken else { return }
        commitLatencyToken = nil
        KeyboardLatencyRecorder.production.finish(token)
    }

    private func cancelActiveLatencyMeasurements() {
        if let token = feedbackLatencyToken {
            feedbackLatencyToken = nil
            KeyboardLatencyRecorder.production.cancel(token)
        }
        if let token = commitLatencyToken {
            commitLatencyToken = nil
            KeyboardLatencyRecorder.production.cancel(token)
        }
    }

    private func commit(_ text: String) {
        guard let model else { return }
        if text == " " {
            model.insertSpace()
            return
        }
        if text == activeLiteral,
           text.count == 1,
           let literal = text.first,
           literal.isLetter,
           let activeOrigin,
           let normalized = normalizedKeySpacePoint(
               for: activeOrigin,
               literalKey: literal
           ) {
            model.insertLetter(at: normalized, literalKey: literal)
            return
        }
        model.insertLiteralCharacter(text)
    }

    private func commitSwipe() {
        defer {
            swipePoints = []
            swipeSampleBuffer.removeAll()
        }
        guard swipeSampleBuffer.samples.count >= 2 else { return }
        model?.commitSwipe(samples: swipeSampleBuffer.samples)
    }

    private func appendSwipeSample(_ point: CGPoint, timestamp: TimeInterval) {
        appendBoundedSwipePoint(point)
        guard let normalized = normalizedKeySpacePoint(
            for: point,
            literalKey: nil
        ) else { return }
        let timestampMilliseconds = max(
            timestamp * 1_000,
            swipeSampleBuffer.samples.last?.timestampMilliseconds ?? -.infinity
        )
        let sample = SwipePathSample(
            point: normalized,
            timestampMilliseconds: timestampMilliseconds
        )
        guard swipeSampleBuffer.samples.last != sample else { return }
        swipeSampleBuffer.append(sample)
    }

    private func beginSwipe(at origin: CGPoint, eventTime: TimeInterval) {
        if pendingPointerSamples.isEmpty {
            pendingPointerSamples = [(origin, activeDownTime ?? eventTime)]
        }
        swipePoints = []
        swipeSampleBuffer.removeAll()
        for (point, timestamp) in pendingPointerSamples {
            appendSwipeSample(point, timestamp: timestamp)
        }
    }

    private func recordPointerSample(_ point: CGPoint, timestamp: TimeInterval) {
        if let last = pendingPointerSamples.last,
           last.0 == point,
           last.1 == timestamp {
            return
        }
        pendingPointerSamples.append((point, timestamp))
        if pendingPointerSamples.count > Self.maximumLiveSwipeSamples {
            // Preserve the exact down sample while bounding a pathological
            // high-frequency gesture's memory use.
            pendingPointerSamples.remove(at: 1)
        }
    }

    private func appendBoundedSwipePoint(_ point: CGPoint) {
        guard swipePoints.last != point else { return }
        swipePoints.append(point)
        guard swipePoints.count > Self.maximumLiveSwipeSamples else { return }
        let interior = swipePoints.indices.dropFirst().dropLast()
        let removalIndex = interior.min { lhs, rhs in
            rawPointRedundancy(at: lhs) < rawPointRedundancy(at: rhs)
        } ?? 1
        swipePoints.remove(at: removalIndex)
    }

    private func rawPointRedundancy(at index: Int) -> CGFloat {
        let previous = swipePoints[index - 1]
        let current = swipePoints[index]
        let next = swipePoints[index + 1]
        return hypot(previous.x - current.x, previous.y - current.y)
            + hypot(current.x - next.x, current.y - next.y)
            - hypot(previous.x - next.x, previous.y - next.y)
    }

    private func schedule(_ deadline: KeyboardInteractionDeadline) {
        deadlineTasks[deadline.token]?.cancel()
        let delay = max(
            0,
            deadline.dueTime - ProcessInfo.processInfo.systemUptime
        )
        deadlineTasks[deadline.token] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            deadlineTasks[deadline.token] = nil
            apply(
                router.handle(.deadline(deadline)),
                eventTime: deadline.dueTime
            )
        }
    }

    private func cancelDeadlines() {
        for task in deadlineTasks.values {
            task.cancel()
        }
        deadlineTasks.removeAll()
    }

    private func normalizedKeySpacePoint(
        for point: CGPoint,
        literalKey: Character?
    ) -> CGPoint? {
        guard let q = keyFrames["q"], let p = keyFrames["p"],
              let a = keyFrames["a"], let l = keyFrames["l"],
              let z = keyFrames["z"], let m = keyFrames["m"] else {
            return nil
        }

        let topY = (q.midY + p.midY) / 2
        let middleY = (a.midY + l.midY) / 2
        let bottomY = (z.midY + m.midY) / 2
        guard middleY > topY, bottomY > middleY else { return nil }
        let normalizedY = point.y <= middleY
            ? (point.y - topY) / (middleY - topY)
            : 1 + (point.y - middleY) / (bottomY - middleY)

        let inferredRow = Int(min(2, max(0, normalizedY.rounded())))
        let row = literalKey
            .flatMap { QwertyKeyLayout.position(of: $0) }
            .map { Int($0.y.rounded()) }
            ?? inferredRow
        let horizontal: (first: CGRect, last: CGRect, firstX: CGFloat, steps: CGFloat)
        switch row {
        case 1:
            horizontal = (a, l, 0.25, 8)
        case 2:
            horizontal = (z, m, 0.75, 6)
        default:
            horizontal = (q, p, 0, 9)
        }
        let xScale = (horizontal.last.midX - horizontal.first.midX) / horizontal.steps
        guard xScale > 0 else { return nil }
        return CGPoint(
            x: horizontal.firstX + (point.x - horizontal.first.midX) / xScale,
            y: normalizedY
        )
    }
}

private extension InteractionPoint {
    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct KeyboardKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(
                configuration.isPressed
                    ? Color(uiColor: .systemGray3)
                    : Color(uiColor: .systemBackground)
            )
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
            .foregroundStyle(
                isHighlighted ? Color(uiColor: .systemBackground) : Color.primary
            )
            .background(
                isHighlighted
                    ? Color.primary.opacity(configuration.isPressed ? 0.6 : 0.85)
                    : configuration.isPressed
                        ? Color(uiColor: .systemGray2)
                        : Color(uiColor: .systemGray3)
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
                    : Color(
                        uiColor: configuration.isPressed
                            ? .systemGray3
                            : .systemBackground
                    )
            )
            .clipShape(.rect(cornerRadius: 8))
    }
}
