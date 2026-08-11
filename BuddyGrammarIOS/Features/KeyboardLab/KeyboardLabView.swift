import BuddyGrammarKit
import SwiftUI

struct KeyboardLabView: View {
    private static let sampleText =
        "i really enjoy writing with buddygrammar it makes everything easier"

    @State private var model = KeyboardLabModel()
    @State private var freeformText = sampleText
    @FocusState private var isPracticeEditorFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    AdaptivePracticeCard(
                        model: model,
                        isEditorFocused: $isPracticeEditorFocused
                    )
                    freeformCard
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Keyboard Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isPracticeEditorFocused) { _, isFocused in
            model.setPracticeEditorActive(isFocused)
        }
        .onDisappear {
            model.endSession()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            isPracticeEditorFocused = false
            model.endSession()
        }
        .accessibilityIdentifier("keyboardLab.screen")
    }

    private var introduction: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("A keyboard that learns with you", systemImage: "sparkles")
                    .font(.title3.bold())
                    .foregroundStyle(Color.buddyAccent)
                Text(
                    "Practice targets what needs work next. Responses stay out of your personal vocabulary; only private accuracy totals are saved."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var freeformCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Freeform keyboard test", systemImage: "keyboard.fill")
                    .font(.headline)

                Text(
                    "Switch to BuddyGrammar with the globe key, then hold Return to fix the whole sample."
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $freeformText)
                    .font(.body)
                    .frame(minHeight: 150)
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.buddyAccent.opacity(0.22), lineWidth: 1)
                    }
                    .accessibilityLabel("Keyboard testing text")
                    .accessibilityIdentifier("keyboardLab.input")

                Button("Reset sample", systemImage: "arrow.counterclockwise") {
                    freeformText = Self.sampleText
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("keyboardLab.reset")
            }
        }
    }
}

private struct AdaptivePracticeCard: View {
    @Bindable var model: KeyboardLabModel
    @FocusState.Binding var isEditorFocused: Bool

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                trackPicker
                prompt
                responseEditor
                actions

                if let result = model.result {
                    PracticeResultView(result: result) {
                        model.nextPrompt()
                        isEditorFocused = true
                    }
                }

                if let message = model.persistenceMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("keyboardLab.practice.persistenceMessage")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Adaptive practice", systemImage: "scope")
                .font(.headline)
            Spacer()
            Text("\(model.profile.completedAttempts) done")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(model.profile.completedAttempts) completed practices")
        }
    }

    private var trackPicker: some View {
        Picker("Practice focus", selection: $model.selectedTrack) {
            ForEach(PracticeTrack.allCases, id: \.self) { track in
                Text(track.title).tag(track)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("keyboardLab.practice.track")
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.prompt.instruction)
                .font(.subheadline.weight(.semibold))
            if let stimulus = model.prompt.stimulus {
                Text(stimulus)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.buddyAccent.opacity(0.09), in: .rect(cornerRadius: 12))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keyboardLab.practice.prompt")
    }

    private var responseEditor: some View {
        TextEditor(text: $model.response)
            .font(.body)
            .frame(minHeight: 112)
            .padding(10)
            .scrollContentBackground(.hidden)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.buddyAccent.opacity(isEditorFocused ? 0.6 : 0.2), lineWidth: 1)
            }
            .focused($isEditorFocused)
            .textInputAutocapitalization(.sentences)
            .disabled(model.result != nil)
            .accessibilityLabel("Practice response")
            .accessibilityHint("Use the BuddyGrammar keyboard to enter your answer")
            .accessibilityIdentifier("keyboardLab.practice.input")
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Submit", systemImage: "checkmark") {
                model.submit()
            }
            .buttonStyle(.borderedProminent)
            .tint(.buddyAccent)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("keyboardLab.practice.submit")

            Button("Skip") {
                model.skipPrompt()
            }
            .buttonStyle(.bordered)
            .disabled(model.result != nil)
            .accessibilityIdentifier("keyboardLab.practice.skip")

            Button("Reset", systemImage: "arrow.counterclockwise") {
                model.resetSession()
                isEditorFocused = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled(model.response.isEmpty && model.result == nil)
            .accessibilityLabel("Reset practice answer")
            .accessibilityIdentifier("keyboardLab.practice.reset")
        }
    }
}

private struct PracticeResultView: View {
    let result: PracticeResult
    let showNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Attempt scored", systemImage: "chart.bar.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.buddyAccent)

            HStack(spacing: 12) {
                AccuracyMetric(title: "Typed accuracy", value: result.rawAccuracy)
                AccuracyMetric(
                    title: "Learning evidence",
                    value: min(1, result.evidenceWeight / 1.5)
                )
            }

            Button("Next practice", systemImage: "arrow.right", action: showNext)
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("keyboardLab.practice.next")
        }
        .padding(14)
        .background(Color.buddyAccent.opacity(0.08), in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("keyboardLab.practice.result")
    }
}

private struct AccuracyMetric: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

private extension PracticeTrack {
    var title: String {
        switch self {
        case .motor: "Typing"
        case .writing: "Writing"
        case .mixed: "Mixed"
        }
    }
}
