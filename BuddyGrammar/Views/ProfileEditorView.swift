import SwiftUI

struct ProfileEditorView: View {
    let profile: PromptProfile
    let conflictingProfile: PromptProfile?
    let onChange: (PromptProfile) -> Void
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

                // MARK: - Shortcut

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Shortcut")

                    HotkeyRecorderView(
                        hotkey: binding(\.hotkey),
                        conflictLabel: conflictingProfile?.name
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
