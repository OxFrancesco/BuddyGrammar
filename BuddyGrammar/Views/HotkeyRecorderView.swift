import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeyDescriptor?
    var conflictLabel: String?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    toggleRecording()
                } label: {
                    HStack {
                        Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                        Text(isRecording ? "Press Shortcut" : (hotkey?.displayString ?? "Record Shortcut"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    hotkey = nil
                }
                .disabled(hotkey == nil)
            }

            if let conflictLabel {
                Text("This shortcut is already used by \(conflictLabel).")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Use Command, Control, Option, or Shift plus a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
