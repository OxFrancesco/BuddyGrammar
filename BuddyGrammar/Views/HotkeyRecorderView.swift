import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeyDescriptor?
    var conflictLabel: String?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isRecording ? "Press Shortcut" : (hotkey?.displayString ?? "Record Shortcut"))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(isRecording ? Color.white : NeoTheme.foreground)
                    .background(isRecording ? NeoTheme.primary : NeoTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                            .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
                    )
                }
                .buttonStyle(.plain)

                Button("Clear") {
                    hotkey = nil
                }
                .buttonStyle(NeoBrutalistButton(isPrimary: false, isDisabled: hotkey == nil))
                .disabled(hotkey == nil)
            }

            if let conflictLabel {
                Text("This shortcut is already used by \(conflictLabel).")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(NeoTheme.destructive)
            }
        }
        .focusEffectDisabled()
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            guard !modifiers.isEmpty else {
                NSSound.beep()
                return nil
            }

            hotkey = HotkeyDescriptor(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
