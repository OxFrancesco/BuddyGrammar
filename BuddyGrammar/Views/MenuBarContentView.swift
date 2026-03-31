import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BuddyGrammar")
                    .font(.headline)
                Text(model.rewriteCoordinator.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(
                        model.rewriteCoordinator.lastErrorMessage == nil
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(Color.red)
                    )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.settingsStore.profiles) { profile in
                    Button {
                        model.runProfile(profile)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                Text(profile.hotkey?.displayString ?? "No hotkey")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.isEnabled {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!profile.isEnabled)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label(model.hasAPIKey ? "API key saved" : "API key missing", systemImage: model.hasAPIKey ? "checkmark.seal.fill" : "key.slash")
                    .foregroundStyle(model.hasAPIKey ? .green : .secondary)
                Label(model.accessibilityGranted ? "Accessibility granted" : "Accessibility permission missing", systemImage: model.accessibilityGranted ? "hand.raised.fill" : "hand.raised.slash")
                    .foregroundStyle(model.accessibilityGranted ? .green : .secondary)
            }
            .font(.caption)

            Divider()

            HStack {
                Button("Settings") {
                    model.openSettings()
                }
                Button("Onboarding") {
                    model.openOnboarding()
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
