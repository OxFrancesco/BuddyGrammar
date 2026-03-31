import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("BuddyGrammar")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("A menu bar utility that captures your selected text, rewrites it with OpenRouter, and pastes or copies the result.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                onboardingCard(
                    title: "1. Add Your API Key",
                    symbol: "key.radiowaves.forward",
                    detail: "Paste your OpenRouter API key into Settings. The key is stored in Keychain, not in plain text.",
                    actionTitle: "Open Settings",
                    action: model.openSettings
                )

                onboardingCard(
                    title: "2. Allow Accessibility",
                    symbol: "hand.raised.circle",
                    detail: "BuddyGrammar needs Accessibility permission to read and replace text in other apps.",
                    actionTitle: "Open Accessibility",
                    action: model.openAccessibilitySettings
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Default Grammar shortcut: ^⌥G", systemImage: "keyboard")
                Label("You can add more prompt profiles, each with its own hotkey.", systemImage: "plus.square.on.square")
                Label("The top overlay animates while your text is being fixed.", systemImage: "sparkles.rectangle.stack")
            }
            .font(.headline)

            Spacer()

            HStack {
                if model.hasAPIKey && model.accessibilityGranted {
                    Label("You are ready to go.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Finish the two setup steps above, then try the Grammar shortcut in any app.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Continue") {
                    model.completeOnboarding()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.16, blue: 0.23),
                    Color(red: 0.08, green: 0.10, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(.white)
    }

    private func onboardingCard(
        title: String,
        symbol: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.08))
        }
    }
}
