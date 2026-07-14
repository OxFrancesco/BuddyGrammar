import SwiftUI
import UIKit

struct OnboardingView: View {
    @Bindable var model: IOSAppModel
    @Environment(\.openURL) private var openURL
    @State private var acceptsCloudProcessing = true

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                WaveformMark(barWidth: 7)
                    .frame(height: 44)

                Text("BuddyGrammar")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .padding(.top, 18)

                Text("Speak or type in any app. BuddyGrammar turns it into clean, corrected text.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 14) {
                    SetupRow(
                        symbol: "keyboard",
                        text: "Add the keyboard in Settings → General → Keyboard, then turn on Allow Full Access"
                    )
                    SetupRow(
                        symbol: "waveform.badge.mic",
                        text: "Tap the mic key to dictate, or ★ to fix a sentence"
                    )
                    SetupRow(
                        symbol: "lock",
                        text: "Typing stays on-device. Audio and ★ text go to the cloud only when you ask"
                    )
                }
                .padding(.top, 32)

                Spacer()

                Toggle(isOn: $acceptsCloudProcessing) {
                    Text("Allow cloud processing for dictation and ★")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("onboarding.cloudConsent")
                .padding(.bottom, 16)

                Button("Open Settings", systemImage: "arrow.up.forward.app") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("onboarding.openSettings")
                .padding(.bottom, 16)

                Button("Start writing") {
                    model.completeOnboarding(
                        acceptsCloudProcessing: acceptsCloudProcessing
                    )
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("onboarding.complete")
            }
            .padding(24)
        }
        .accessibilityIdentifier("onboarding.screen")
    }
}

private struct SetupRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.buddyAccent)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
