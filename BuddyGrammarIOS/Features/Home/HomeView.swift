import SwiftUI

private enum HomeRoute: Hashable {
    case keyboardLab
}

struct HomeView: View {
    @Bindable var model: IOSAppModel

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    statusRow
                    dictateAction
                    quickDictationRow
                    pendingTranscriptRow
                    keyboardLabRow
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("BuddyGrammar")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .keyboardLab:
                KeyboardLabView()
            }
        }
        .accessibilityIdentifier("home.screen")
    }

    private var header: some View {
        HStack(spacing: 16) {
            WaveformMark(
                isAnimating: model.dictationPhase.isRecording,
                barWidth: 5
            )
            .frame(height: 30)

            Text(model.dictationPhase.isRecording ? "Listening…" : "Ready when you are")
                .font(.system(.title3, design: .rounded, weight: .semibold))
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusRow: some View {
        if !model.isCloudReady {
            Button {
                model.selectedTab = .settings
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.orange)
                    Text(
                        model.isSharedContainerReady
                            ? "Allow cloud processing to finish setup"
                            : "Reinstall the app to restore keyboard sharing"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.openSettings")
        }
    }

    private var dictateAction: some View {
        Button {
            model.selectedTab = .dictation
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.title3.weight(.semibold))
                Text("Dictate")
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(Color.buddyAccent, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.startDictation")
    }

    private var quickDictationRow: some View {
        Toggle(isOn: quickDictationBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Skip app switching")
                    .font(.subheadline.weight(.medium))
                Text("Keeps the mic ready in a tucked-away window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityIdentifier("home.quickDictation")
    }

    @ViewBuilder
    private var pendingTranscriptRow: some View {
        if !model.transcriptDraft.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(
                        model.pendingTranscript == nil
                            ? "Saved locally"
                            : "Saved locally and for the keyboard"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", role: .destructive) {
                        model.clearTranscript()
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("home.clearPending")
                }
                Text(model.transcriptDraft)
                    .font(.subheadline)
                    .lineLimit(3)
                    .accessibilityIdentifier("home.pendingTranscript")
            }
            .padding(16)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }

    private var keyboardLabRow: some View {
        NavigationLink(value: HomeRoute.keyboardLab) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard")
                    .foregroundStyle(Color.buddyAccent)
                Text("Try the keyboard")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.openKeyboardLab")
    }

    private var quickDictationBinding: Binding<Bool> {
        Binding(
            get: { model.settings.enablesQuickDictation },
            set: { model.setQuickDictation(enabled: $0) }
        )
    }
}
