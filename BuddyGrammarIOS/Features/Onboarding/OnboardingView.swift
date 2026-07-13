import SwiftUI
import UIKit

struct OnboardingView: View {
    @Bindable var model: IOSAppModel
    @Environment(\.openURL) private var openURL
    @State private var page = 0
    @State private var acceptsCloudProcessing = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 20) {
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index <= page ? Color.buddyAccent : Color.secondary.opacity(0.2))
                            .frame(height: 5)
                    }
                }
                .accessibilityLabel("Step \(page + 1) of 3")

                TabView(selection: $page) {
                    WelcomePage()
                        .tag(0)
                    StarKeyPage()
                        .tag(1)
                    KeyboardSetupPage()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 12) {
                    if page == 2 {
                        Toggle(isOn: $acceptsCloudProcessing) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Allow cloud processing")
                                    .font(.subheadline.weight(.semibold))
                                Text("Required when you request ElevenLabs dictation or OpenRouter correction.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(14)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                        .accessibilityIdentifier("onboarding.cloudConsent")

                        Button("Open Settings", systemImage: "gearshape") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("onboarding.openSettings")

                        Button("Finish setup", systemImage: "checkmark") {
                            model.completeOnboarding(
                                acceptsCloudProcessing: acceptsCloudProcessing
                            )
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .accessibilityIdentifier("onboarding.complete")
                    } else {
                        Button("Continue", systemImage: "arrow.right") {
                            withAnimation(.snappy) {
                                page += 1
                            }
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .accessibilityIdentifier("onboarding.continue")
                    }
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("onboarding.screen")
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.buddyAccentSoft)
                    .frame(width: 136, height: 136)
                Image(systemName: "star.fill")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(Color.buddyAccent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Write clearly, anywhere")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("BuddyGrammar adds a smart star key and voice dictation to your iPhone keyboard.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }
}

private struct StarKeyPage: View {
    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Image(systemName: "keyboard.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.buddyAccent)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Tap ★ to fix your sentence")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("The keyboard corrects the selected text—or your most recent sentence—while keeping your language and voice.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            AppCard {
                Label("Normal typing stays on-device. Text is sent through BuddyGrammar to OpenRouter only when you tap the star.", systemImage: "hand.tap.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct KeyboardSetupPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.buddyAccent)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Enable the keyboard")
                        .font(.largeTitle.bold())
                    Text("Apple requires this one-time step.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 18) {
                        SetupStep(number: 1, text: "Open Settings → General → Keyboard")
                        SetupStep(number: 2, text: "Tap Keyboards → Add New Keyboard")
                        SetupStep(number: 3, text: "Choose BuddyGrammar, then enable Allow Full Access")
                    }
                }

                Label(
                    "Full Access lets the keyboard contact the BuddyGrammar service and read the transcript shared by this app.",
                    systemImage: "lock.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.buddyAccent, in: .circle)
            Text(text)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
