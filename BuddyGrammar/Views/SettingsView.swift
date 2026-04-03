import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selectedTab: Tab = .general

    private enum Tab: String, CaseIterable, Identifiable {
        case general, openRouter, personalities
        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .openRouter: "OpenRouter"
            case .personalities: "Personalities"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .openRouter: "key.horizontal"
            case .personalities: "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 170, idealWidth: 190, maxWidth: 220)
                .padding(16)

            Rectangle()
                .fill(NeoTheme.border)
                .frame(width: 1)
                .padding(.vertical, 16)

            ZStack {
                tabContent
                    .id(selectedTab)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NeoTheme.background)
        .foregroundStyle(NeoTheme.foreground)
        .focusEffectDisabled()
        .animation(.easeInOut(duration: 0.15), value: selectedTab)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BuddyGrammar")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .tracking(-0.3)
                .foregroundStyle(NeoTheme.foreground)
                .padding(.bottom, 8)

            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? NeoTheme.primary : NeoTheme.mutedForeground)
                            .frame(width: 18)

                        Text(tab.title)
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? NeoTheme.foreground : NeoTheme.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? NeoTheme.primary.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }

            Spacer()
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
        case .personalities:
            personalitiesTab
        }
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            neoCard {
                VStack(alignment: .leading, spacing: 16) {
                    neoFormRow(label: "Output mode") {
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
                        Toggle("", isOn: launchAtLoginBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(NeoTheme.primary)
                    }

                    neoDivider

                    neoFormRow(label: "Accessibility") {
                        if model.accessibilityGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NeoTheme.green)
                                .font(.system(size: 16, weight: .semibold))
                        } else {
                            Button {
                                model.openAccessibilitySettings()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Grant Access")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(NeoTheme.orange)
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        }
                    }
                }
            }

            if let error = model.settingsErrorMessage {
                Text(error)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(NeoTheme.destructive)
                    .padding(.top, 10)
            }

            Spacer()

            Text(model.appUpdateService.currentVersionDescription)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NeoTheme.mutedForeground)
        }
    }

    // MARK: - API

    private var apiTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            neoCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
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
                                    .stroke(NeoTheme.border, lineWidth: 1)
                            )
                    }

                    HStack(spacing: 10) {
                        Button("Save Key") {
                            model.saveAPIKey()
                        }
                        .buttonStyle(NeoBrutalistButton())

                        Button("Clear") {
                            model.apiKeyDraft = ""
                            model.saveAPIKey()
                        }
                        .buttonStyle(NeoBrutalistButton(isPrimary: false))
                        .disabled(model.apiKeyDraft.isEmpty && !model.hasAPIKey)

                        if model.hasAPIKey {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Saved")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(NeoTheme.green)
                        }
                    }

                    if let error = model.settingsErrorMessage {
                        Text(error)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(NeoTheme.destructive)
                    }

                    neoDivider

                    featurePill(symbol: "cpu", label: "openai/gpt-5.4-nano")
                }
            }

            Spacer()
        }
    }

    // MARK: - Personalities

    private var personalitiesTab: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 2) {
                    ForEach(model.settingsStore.profiles) { profile in
                        Button {
                            model.selectedProfileID = profile.id
                        } label: {
                            HStack(spacing: 8) {
                                Text(profile.name)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                Spacer()
                                Text(profile.hotkey?.displayString ?? "—")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(NeoTheme.mutedForeground)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(model.selectedProfileID == profile.id ? NeoTheme.primary.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                }
                .padding(6)
                .modifier(NeoBrutalistCard())

                HStack(spacing: 8) {
                    Menu {
                        ForEach(PersonalityTemplate.allCases) { template in
                            Button {
                                model.addPersonality(template: template)
                            } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(template.title)
                                        Text(templateSubtitle(template))
                                            .font(.caption2)
                                    }
                                } icon: {
                                    Image(systemName: templateSymbol(template))
                                }
                            }
                        }
                    } label: {
                        Text("Add")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .foregroundStyle(NeoTheme.foreground)
                            .background(NeoTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                                    .stroke(NeoTheme.border, lineWidth: NeoTheme.borderWidth)
                            )
                    }
                    .focusEffectDisabled()

                    Button("Delete") {
                        model.deleteSelectedPersonality()
                    }
                    .buttonStyle(NeoBrutalistButton(isPrimary: false, isDisabled: selectedProfile?.isBuiltIn ?? true))
                    .disabled(selectedProfile?.isBuiltIn ?? true)
                }
            }
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 260)

            Group {
                if let profile = selectedProfile {
                    ProfileEditorView(
                        profile: profile,
                        conflictingProfile: model.settingsStore.hotkeyConflict(for: profile.id, hotkey: profile.hotkey),
                        onChange: { updated in
                            model.settingsStore.update(updated)
                        },
                        onMoveUp: {
                            model.moveSelectedPersonality(.up)
                        },
                        onMoveDown: {
                            model.moveSelectedPersonality(.down)
                        },
                        onDelete: profile.isBuiltIn ? nil : {
                            model.deleteSelectedPersonality()
                        }
                    )
                    .id(profile.id)
                } else {
                    ContentUnavailableView("No Personality Selected", systemImage: "slider.horizontal.below.rectangle")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func templateSymbol(_ template: PersonalityTemplate) -> String {
        switch template {
        case .formal:
            "text.alignleft"
        case .email:
            "envelope"
        case .twitterPost:
            "bubble.left.and.bubble.right"
        case .blankCustom:
            "sparkles"
        }
    }

    private func templateSubtitle(_ template: PersonalityTemplate) -> String {
        switch template {
        case .formal:
            "Polished, formal wording"
        case .email:
            "Professional email draft"
        case .twitterPost:
            "Short social post"
        case .blankCustom:
            "Start from a blank prompt"
        }
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
