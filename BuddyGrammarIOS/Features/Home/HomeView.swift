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
                VStack(alignment: .leading, spacing: 18) {
                    header
                    readinessCard
                    quickActions
                    pendingTranscriptCard
                    starKeyCard
                }
                .padding(18)
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
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.buddyAccent)
                    .frame(width: 64, height: 64)
                Image(systemName: "star.fill")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your writing copilot")
                    .font(.title2.bold())
                Text("Correct and dictate from any app.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var readinessCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cloud features")
                            .font(.headline)
                        Text(model.isCloudReady ? "Ready to correct and dictate" : "Finish setup to unlock every feature")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: model.isCloudReady ? "checkmark.seal.fill" : "sparkles")
                        .font(.title2)
                        .foregroundStyle(model.isCloudReady ? Color.green : Color.buddyAccent)
                }

                HStack(spacing: 8) {
                    StatusBadge(title: "Service", isReady: true)
                    StatusBadge(
                        title: "Consent",
                        isReady: model.settings.hasAcceptedCloudProcessing
                    )
                    StatusBadge(title: "Keyboard", isReady: model.isSharedContainerReady)
                }

                if !model.isCloudReady {
                    Button("Open Settings", systemImage: "arrow.right") {
                        model.selectedTab = .settings
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("home.openSettings")
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                model.selectedTab = .dictation
            } label: {
                QuickActionLabel(
                    title: "Dictate",
                    subtitle: "Speech to text",
                    systemImage: "waveform",
                    tint: .buddyAccent
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.startDictation")

            NavigationLink(value: HomeRoute.keyboardLab) {
                QuickActionLabel(
                    title: "Keyboard Lab",
                    subtitle: "Try the star key",
                    systemImage: "keyboard",
                    tint: .indigo
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.openKeyboardLab")
        }
    }

    @ViewBuilder
    private var pendingTranscriptCard: some View {
        if let transcript = model.pendingTranscript {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Ready for keyboard", systemImage: "text.cursor")
                            .font(.headline)
                        Spacer()
                        Text(transcript.createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(transcript.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .accessibilityIdentifier("home.pendingTranscript")

                    Button("Clear", systemImage: "trash", role: .destructive) {
                        model.clearTranscript()
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("home.clearPending")
                }
            }
        }
    }

    private var starKeyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("How the star works", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(Color.buddyAccent)
                Text("Select text, or place the cursor after a sentence, then tap ★. BuddyGrammar replaces only that text after the correction is ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("The keyboard keeps working normally when Full Access is off.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct QuickActionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}
