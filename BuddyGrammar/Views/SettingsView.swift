import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            apiTab
                .tabItem {
                    Label("OpenRouter", systemImage: "key")
                }

            profilesTab
                .tabItem {
                    Label("Profiles", systemImage: "slider.horizontal.3")
                }
        }
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Picker("When a rewrite finishes", selection: outputModeBinding) {
                ForEach(OutputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Overlay motion", selection: overlayMotionBinding) {
                ForEach(OverlayMotionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Toggle("Launch at login", isOn: launchAtLoginBinding)

            VStack(alignment: .leading, spacing: 8) {
                Label(model.accessibilityGranted ? "Accessibility is enabled." : "Accessibility permission is still required.", systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                Button("Open Accessibility Settings") {
                    model.openAccessibilitySettings()
                }
            }

            if let settingsErrorMessage = model.settingsErrorMessage {
                Text(settingsErrorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var apiTab: some View {
        Form {
            SecureField("OpenRouter API Key", text: $model.apiKeyDraft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save Key") {
                    model.saveAPIKey()
                }
                Button("Clear Key", role: .destructive) {
                    model.apiKeyDraft = ""
                    model.saveAPIKey()
                }
                .disabled(model.apiKeyDraft.isEmpty && !model.hasAPIKey)
            }

            Text("BuddyGrammar uses OpenRouter with the fixed model `openai/gpt-5.4-nano` in v1.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.hasAPIKey {
                Label("An API key is stored in Keychain.", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }

            if let settingsErrorMessage = model.settingsErrorMessage {
                Text(settingsErrorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var profilesTab: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                List(selection: $model.selectedProfileID) {
                    ForEach(model.settingsStore.profiles) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                            Text(profile.hotkey?.displayString ?? "No shortcut")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(profile.id)
                    }
                }
                .frame(minWidth: 220)

                HStack {
                    Button("Add") {
                        model.addProfile()
                    }
                    Button("Delete", role: .destructive) {
                        model.deleteSelectedProfile()
                    }
                    .disabled(selectedProfile?.isBuiltIn ?? true)
                }
            }
            .frame(minWidth: 240)

            Group {
                if let profile = selectedProfile {
                    ProfileEditorView(
                        profile: profile,
                        conflictingProfile: model.settingsStore.hotkeyConflict(for: profile.id, hotkey: profile.hotkey),
                        onChange: { updated in
                            model.settingsStore.update(updated)
                        },
                        onMoveUp: {
                            model.moveSelectedProfile(.up)
                        },
                        onMoveDown: {
                            model.moveSelectedProfile(.down)
                        },
                        onDelete: profile.isBuiltIn ? nil : {
                            model.deleteSelectedProfile()
                        }
                    )
                } else {
                    ContentUnavailableView("No Profile Selected", systemImage: "slider.horizontal.below.rectangle")
                }
            }
            .frame(minWidth: 460)
        }
    }

    private var selectedProfile: PromptProfile? {
        guard let id = model.selectedProfileID else { return nil }
        return model.settingsStore.profile(id: id)
    }

    private var outputModeBinding: Binding<OutputMode> {
        Binding(
            get: { model.settingsStore.appSettings.outputMode },
            set: { newValue in
                model.settingsStore.appSettings.outputMode = newValue
            }
        )
    }

    private var overlayMotionBinding: Binding<OverlayMotionMode> {
        Binding(
            get: { model.settingsStore.appSettings.overlayMotionMode },
            set: { newValue in
                model.settingsStore.appSettings.overlayMotionMode = newValue
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.settingsStore.appSettings.launchAtLogin },
            set: { newValue in
                model.settingsStore.appSettings.launchAtLogin = newValue
            }
        )
    }
}
