import SwiftUI

struct ProfileEditorView: View {
    let profile: PromptProfile
    let conflictingProfile: PromptProfile?
    let onChange: (PromptProfile) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Form {
            Section("Personality") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if profile.isStandard {
                        readonlyCard(text: profile.name)
                    } else {
                        TextField("Label", text: binding(\.name))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("System Prompt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if profile.isStandard {
                        readonlyCard(text: profile.instruction, minHeight: 140)
                    } else {
                        TextEditor(text: binding(\.instruction))
                            .font(.body)
                            .frame(minHeight: 140)
                    }
                }

                Toggle("Enabled", isOn: binding(\.isEnabled))
                    .disabled(profile.hotkey == nil)
            }

            Section("Shortcut") {
                HotkeyRecorderView(
                    hotkey: binding(\.hotkey),
                    conflictLabel: conflictingProfile?.name
                )
            }

            Section("Actions") {
                HStack {
                    Button("Move Up", action: onMoveUp)
                        .disabled(profile.isStandard)
                    Button("Move Down", action: onMoveDown)
                        .disabled(profile.isStandard)
                    Spacer()
                    if let onDelete {
                        Button("Delete", role: .destructive, action: onDelete)
                            .disabled(profile.isBuiltIn)
                    }
                }
            }

            Section {
                Text("Templates are starting points. You can customize the label, system prompt, and shortcut after adding one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if profile.isStandard {
                Section {
                    Text("Standard is built in. Its label and system prompt are fixed, but you can change its shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func readonlyCard(text: String, minHeight: CGFloat? = nil) -> some View {
        ScrollView {
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(minHeight: minHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
