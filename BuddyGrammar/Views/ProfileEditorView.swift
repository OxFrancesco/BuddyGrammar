import SwiftUI

struct ProfileEditorView: View {
    let profile: PromptProfile
    let conflictLabel: String?
    let openRouterModels: [OpenRouterModelSummary]
    let defaultOpenRouterModelID: String
    let modelsAreLoading: Bool
    let modelsErrorMessage: String?
    let onChange: (PromptProfile) -> Void
    let onRefreshModels: @MainActor () async -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Personality

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Personality")

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Label")

                        if profile.isStandard {
                            readonlyCard(text: profile.name)
                        } else {
                            TextField("Label", text: binding(\.name))
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .padding(10)
                                .background(NeoTheme.muted)
                                .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                                        .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("System Prompt")

                        if profile.isStandard {
                            readonlyCard(text: profile.instruction, minHeight: 140)
                        } else {
                            TextEditor(text: binding(\.instruction))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(NeoTheme.foreground)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(minHeight: 140)
                                .background(NeoTheme.muted)
                                .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                                        .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
                                )
                        }
                    }

                    HStack {
                        Text("Enabled")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(NeoTheme.foreground)
                        Spacer()
                        Toggle("", isOn: binding(\.isEnabled))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(NeoTheme.primary)
                            .disabled(profile.hotkey == nil)
                    }
                }
                .padding(16)
                .modifier(NeoBrutalistCard())

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("OpenRouter Model")

                    OpenRouterModelPicker(
                        selection: binding(\.openRouterModelID),
                        defaultModelID: defaultOpenRouterModelID,
                        models: openRouterModels,
                        isLoading: modelsAreLoading,
                        errorMessage: modelsErrorMessage,
                        onRefresh: onRefreshModels
                    )

                    Text("This personality uses the app default unless you choose an override. Local Models ignore this setting.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(NeoTheme.mutedForeground)
                }
                .padding(16)
                .modifier(NeoBrutalistCard())

                // MARK: - Shortcut

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Shortcut")

                    HotkeyRecorderView(
                        hotkey: binding(\.hotkey),
                        conflictLabel: conflictLabel
                    )
                }
                .padding(16)
                .modifier(NeoBrutalistCard())

                // MARK: - Actions

                HStack(spacing: 8) {
                    Button("Move Up", action: onMoveUp)
                        .buttonStyle(NeoBrutalistButton(isPrimary: false, isDisabled: profile.isStandard))
                        .disabled(profile.isStandard)

                    Button("Move Down", action: onMoveDown)
                        .buttonStyle(NeoBrutalistButton(isPrimary: false, isDisabled: profile.isStandard))
                        .disabled(profile.isStandard)

                    Spacer()

                    if let onDelete {
                        Button("Delete", action: onDelete)
                            .buttonStyle(NeoBrutalistButton(isPrimary: false, isDisabled: profile.isBuiltIn))
                            .foregroundStyle(profile.isBuiltIn ? NeoTheme.mutedForeground : NeoTheme.destructive)
                            .disabled(profile.isBuiltIn)
                    }
                }
            }
            .padding(16)
        }
        .background(NeoTheme.background)
        .focusEffectDisabled()
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(NeoTheme.mutedForeground)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(NeoTheme.mutedForeground)
    }

    private func readonlyCard(text: String, minHeight: CGFloat? = nil) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(NeoTheme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(minHeight: minHeight)
        .background(NeoTheme.muted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                .stroke(NeoTheme.border, lineWidth: NeoTheme.borderWidth)
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PromptProfile, Value>) -> Binding<Value> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { newValue in
                var updated = profile
                updated[keyPath: keyPath] = newValue
                if updated.hotkey == nil {
                    updated.isEnabled = false
                }
                onChange(updated)
            }
        )
    }
}

private struct OpenRouterModelPicker: View {
    @Binding var selection: String?
    let defaultModelID: String
    let models: [OpenRouterModelSummary]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: @MainActor () async -> Void

    @State private var isPresented = false
    @State private var query = ""

    private var selectedModel: OpenRouterModelSummary? {
        models.first { $0.id == selection }
    }

    private var filteredModels: [OpenRouterModelSummary] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return models }
        return models.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NeoTheme.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedModel?.displayName ?? selection ?? "App Default")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(NeoTheme.foreground)
                        .lineLimit(1)
                    Text(selection ?? defaultModelID)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(NeoTheme.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NeoTheme.mutedForeground)
            }
            .padding(10)
            .background(NeoTheme.muted)
            .clipShape(.rect(cornerRadius: NeoTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                    .stroke(NeoTheme.border, lineWidth: NeoTheme.borderWidth)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            modelList
                .frame(width: 420, height: 460)
        }
    }

    private var modelList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search OpenRouter models", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        query = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            List {
                modelRow(
                    title: "App Default",
                    subtitle: defaultModelID,
                    modelID: nil
                )

                if isLoading, models.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading models…")
                    }
                    .foregroundStyle(.secondary)
                } else if let errorMessage, models.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await onRefresh() }
                        }
                    }
                } else if filteredModels.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(filteredModels) { model in
                        modelRow(
                            title: model.displayName,
                            subtitle: model.id,
                            modelID: model.id
                        )
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text("\(models.count) text models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await onRefresh() }
                }
                .disabled(isLoading)
            }
            .padding(10)
        }
    }

    private func modelRow(title: String, subtitle: String, modelID: String?) -> some View {
        Button {
            selection = modelID
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == modelID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection == modelID ? NeoTheme.primary : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
