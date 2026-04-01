import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selectedTab: Tab = .general

    private enum Tab: String, CaseIterable, Identifiable {
        case general, openRouter, profiles
        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .openRouter: "OpenRouter"
            case .profiles: "Profiles"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .openRouter: "key.horizontal"
            case .profiles: "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)
                .padding(16)

            Divider()
                .frame(width: NeoTheme.borderWidth)
                .background(NeoTheme.foreground)
                .padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                Divider()
                    .frame(height: NeoTheme.borderWidth)
                    .background(NeoTheme.border)
                    .padding(.horizontal, 24)

                ZStack {
                    tabContent
                        .id(selectedTab)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NeoTheme.background)
        .foregroundStyle(NeoTheme.foreground)
        .animation(.easeInOut(duration: 0.15), value: selectedTab)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BuddyGrammar")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .tracking(-0.3)
                .foregroundStyle(NeoTheme.foreground)

            Text("Settings")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(NeoTheme.mutedForeground)
                .padding(.top, 4)

            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedTab == tab ? NeoTheme.primary : NeoTheme.muted)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
                                )
                            Image(systemName: tab.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(selectedTab == tab ? .white : NeoTheme.mutedForeground)
                        }

                        Text(tab.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(selectedTab == tab ? NeoTheme.muted : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                            .stroke(
                                selectedTab == tab ? NeoTheme.foreground : Color.clear,
                                lineWidth: selectedTab == tab ? NeoTheme.borderWidth : 0
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedTab.symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(NeoTheme.primary)

            Text(selectedTab.title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .tracking(-0.3)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .openRouter:
            apiTab
        case .profiles:
            profilesTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        neoCard {
            VStack(alignment: .leading, spacing: 16) {
                neoFormRow(label: "When a rewrite finishes") {
                    Picker("", selection: outputModeBinding) {
                        ForEach(OutputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }

                neoDivider

                neoFormRow(label: "Launch at login") {
                    neoToggle(isOn: launchAtLoginBinding)
                }

                neoDivider

                neoFormRow(label: "Accessibility") {
                    if model.accessibilityGranted {
                        neoStatusBadge(text: "Enabled", icon: "checkmark.circle.fill", color: NeoTheme.green)
                    } else {
                        neoStatusBadge(text: "Required", icon: "exclamationmark.triangle.fill", color: NeoTheme.orange)
                    }
                }

                if !model.accessibilityGranted {
                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                    .buttonStyle(NeoBrutalistButton(isPrimary: false))
                }

                if let settingsErrorMessage = model.settingsErrorMessage {
                    neoStatusBadge(text: settingsErrorMessage, icon: "xmark.circle.fill", color: NeoTheme.destructive)
                }
            }
        }
    }

    // MARK: - API

    private var apiTab: some View {
        neoCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenRouter API Key")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(NeoTheme.mutedForeground)

                    SecureField("sk-or-v1-…", text: $model.apiKeyDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(10)
                        .background(NeoTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                                .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
                        )
                }

                HStack(spacing: 10) {
                    Button("Save Key") {
                        model.saveAPIKey()
                    }
                    .buttonStyle(NeoBrutalistButton())

                    Button("Clear Key") {
                        model.apiKeyDraft = ""
                        model.saveAPIKey()
                    }
                    .buttonStyle(NeoBrutalistButton(isPrimary: false))
                    .disabled(model.apiKeyDraft.isEmpty && !model.hasAPIKey)
                }

                if model.hasAPIKey {
                    neoStatusBadge(text: "Key saved in Keychain", icon: "checkmark.shield.fill", color: NeoTheme.green)
                }

                if let settingsErrorMessage = model.settingsErrorMessage {
                    neoStatusBadge(text: settingsErrorMessage, icon: "xmark.circle.fill", color: NeoTheme.destructive)
                }

                neoDivider

                featurePill(symbol: "cpu", label: "openai/gpt-5.4-nano")
                Text("Fixed model in v1.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(NeoTheme.mutedForeground)
            }
        }
    }

    // MARK: - Profiles

    private var profilesTab: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 2) {
                    ForEach(model.settingsStore.profiles) { profile in
                        Button {
                            model.selectedProfileID = profile.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(NeoTheme.primary)
                                Text(profile.name)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Spacer()
                                Text(profile.hotkey?.displayString ?? "—")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(NeoTheme.mutedForeground)
                            }
                            .padding(10)
                            .background(model.selectedProfileID == profile.id ? NeoTheme.muted : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                                    .stroke(
                                        model.selectedProfileID == profile.id ? NeoTheme.foreground : Color.clear,
                                        lineWidth: model.selectedProfileID == profile.id ? NeoTheme.borderWidth : 0
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .modifier(NeoBrutalistCard())

                HStack(spacing: 8) {
                    Button("Add") {
                        model.addProfile()
                    }
                    .buttonStyle(NeoBrutalistButton(isPrimary: false))

                    Button("Delete") {
                        model.deleteSelectedProfile()
                    }
                    .buttonStyle(NeoBrutalistButton(isPrimary: false, isDisabled: selectedProfile?.isBuiltIn ?? true))
                    .disabled(selectedProfile?.isBuiltIn ?? true)
                }
            }
            .frame(width: 240)

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
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared Components

    private func neoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(NeoBrutalistCard())
    }

    private func neoFormRow<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            trailing()
        }
    }

    private var neoDivider: some View {
        Rectangle()
            .fill(NeoTheme.border)
            .frame(height: 1)
    }

    private func neoToggle(isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(NeoTheme.primary)
    }

    private func neoStatusBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                .stroke(color, lineWidth: NeoTheme.borderWidth)
        )
    }

    private func featurePill(symbol: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NeoTheme.primary)
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(NeoTheme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NeoTheme.muted)
        .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                .stroke(NeoTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Bindings

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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.settingsStore.appSettings.launchAtLogin },
            set: { newValue in
                model.settingsStore.appSettings.launchAtLogin = newValue
            }
        )
    }
}
