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
            Section("Profile") {
                TextField("Name", text: binding(\.name))
                TextEditor(text: binding(\.instruction))
                    .font(.body)
                    .frame(minHeight: 140)
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
                    Button("Move Down", action: onMoveDown)
                    Spacer()
                    if let onDelete {
                        Button("Delete", role: .destructive, action: onDelete)
                            .disabled(profile.isBuiltIn)
                    }
                }
            }

            if profile.isBuiltIn {
                Section {
                    Text("The Grammar profile is built in and cannot be deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
