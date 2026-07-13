import SwiftUI

struct DictationView: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 22) {
                    recorderCard
                    transcriptCard
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Dictation")
        .accessibilityIdentifier("dictation.screen")
    }

    private var recorderCard: some View {
        AppCard {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(phaseTitle)
                        .font(.title2.bold())
                    Text(phaseSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if model.dictationPhase.isProcessing {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.buddyAccent)
                        .frame(width: 94, height: 94)
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
                                .frame(width: 94, height: 94)
                                .shadow(
                                    color: (model.dictationPhase.isRecording ? Color.red : Color.buddyAccent).opacity(0.25),
                                    radius: 18,
                                    y: 8
                                )
                            Image(systemName: model.dictationPhase.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 34, weight: .bold))
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

                    Button("Discard recording", systemImage: "xmark", role: .destructive) {
                        model.cancelRecording()
                    }
                    .accessibilityIdentifier("dictation.cancel")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var transcriptCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Transcript")
                        .font(.headline)
                    Spacer()
                    if let language = model.detectedLanguageCode {
                        Text(language.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.buddyAccent.opacity(0.12), in: .capsule)
                    }
                }

                TextEditor(text: $model.transcriptDraft)
                    .frame(minHeight: 160)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    .accessibilityLabel("Transcript text")
                    .accessibilityIdentifier("dictation.transcriptEditor")

                Button("Save for keyboard", systemImage: "keyboard.badge.ellipsis") {
                    model.saveDraftForKeyboard()
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(model.dictationPhase.isProcessing || model.dictationPhase.isRecording)
                .accessibilityIdentifier("dictation.saveForKeyboard")

                if !model.transcriptDraft.isEmpty {
                    Button("Clear transcript", systemImage: "trash", role: .destructive) {
                        model.clearTranscript()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(model.dictationPhase.isProcessing || model.dictationPhase.isRecording)
                    .accessibilityIdentifier("dictation.clear")
                }
            }
        }
    }

    private var phaseTitle: String {
        switch model.dictationPhase {
        case .idle, .ready:
            "Speak naturally"
        case .recording:
            "Listening…"
        case .transcribing:
            "Transcribing…"
        case .correcting:
            "Polishing your words…"
        }
    }

    private var phaseSubtitle: String {
        switch model.dictationPhase {
        case .idle, .ready:
            "Tap the microphone, speak, then tap stop."
        case .recording:
            "Tap stop when you’re finished."
        case .transcribing:
            "ElevenLabs is turning speech into text."
        case .correcting:
            "OpenRouter is fixing grammar and punctuation."
        }
    }

    private func elapsedTime(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
