import SwiftUI

struct DictationView: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 28) {
                    recorder
                    transcript
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Dictate")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("dictation.screen")
    }

    private var recorder: some View {
        VStack(spacing: 22) {
            WaveformMark(
                isAnimating: model.dictationPhase.isRecording,
                barWidth: 6
            )
            .frame(height: 34)
            .padding(.top, 16)

            Text(phaseTitle)
                .font(.system(.title2, design: .rounded, weight: .bold))

            if model.isKeyboardDictationActive {
                Label(
                    "Swipe back to the app you were typing in — the recording keeps going. Stop from the keyboard and your words will be inserted.",
                    systemImage: "arrow.uturn.backward"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("dictation.keyboardHandoffHint")
            }

            if model.dictationPhase.isProcessing {
                ProgressView()
                    .controlSize(.large)
                    .tint(.buddyAccent)
                    .frame(width: 92, height: 92)
            } else {
                Button {
                    Task {
                        if model.dictationPhase.isRecording {
                            await model.finishDictation()
                        } else {
                            await model.startDictation()
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(model.dictationPhase.isRecording ? Color.red : Color.buddyAccent)
                            .frame(width: 92, height: 92)
                        Image(systemName: model.dictationPhase.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.dictationPhase.isRecording ? "Stop recording" : "Start recording")
                .accessibilityIdentifier("dictation.recordButton")
            }

            if case .recording(let startedAt) = model.dictationPhase {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedTime(from: startedAt, to: context.date))
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.red)
                }

                Button("Discard", systemImage: "xmark", role: .destructive) {
                    model.cancelRecording()
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("dictation.cancel")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var transcript: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let language = model.detectedLanguageCode {
                    Text(language.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(Color.buddyAccent)
                }
            }

            TextEditor(text: $model.transcriptDraft)
                .frame(minHeight: 150)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
                .accessibilityLabel("Transcript text")
                .accessibilityIdentifier("dictation.transcriptEditor")

            Button("Save for keyboard") {
                model.saveDraftForKeyboard()
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(model.dictationPhase.isProcessing || model.dictationPhase.isRecording)
            .accessibilityIdentifier("dictation.saveForKeyboard")

            if !model.transcriptDraft.isEmpty {
                Button("Clear", role: .destructive) {
                    model.clearTranscript()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .disabled(model.dictationPhase.isProcessing || model.dictationPhase.isRecording)
                .accessibilityIdentifier("dictation.clear")
            }
        }
    }

    private var phaseTitle: String {
        switch model.dictationPhase {
        case .idle, .ready:
            "Tap and speak"
        case .recording:
            "Listening…"
        case .transcribing:
            "Transcribing…"
        case .correcting:
            "Polishing…"
        }
    }

    private func elapsedTime(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
