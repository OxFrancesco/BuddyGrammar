import SwiftUI

struct KeyboardRootView: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge

    var body: some View {
        VStack(spacing: 7) {
            KeyboardAccessoryBar(model: model)

            switch model.layoutMode {
            case .letters:
                LetterKeyboardRows(model: model)
            case .symbols:
                SymbolKeyboardRows(model: model)
            }

            KeyboardControlRow(model: model, controllerBridge: controllerBridge)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 7)
        .background(Color(uiColor: .systemGray5))
    }
}

private struct KeyboardAccessoryBar: View {
    let model: KeyboardModel

    var body: some View {
        HStack(spacing: 8) {
            StatusIndicator(status: model.status)

            Spacer(minLength: 4)

            Button(action: model.insertPendingTranscript) {
                Image(systemName: "waveform.badge.mic")
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(KeyboardAccessoryButtonStyle())
            .accessibilityLabel("Insert latest BuddyGrammar dictation")
            .accessibilityHint("Inserts the latest transcript recorded in the BuddyGrammar app")

            Button(action: model.correctCurrentText) {
                Group {
                    if model.status == .correcting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "star.fill")
                    }
                }
                .frame(width: 40, height: 30)
            }
            .buttonStyle(KeyboardAccessoryButtonStyle(isProminent: true))
            .disabled(model.status == .correcting)
            .accessibilityIdentifier("keyboard.star")
            .accessibilityLabel("Correct text")
            .accessibilityHint("Corrects selected text, or the sentence immediately before the cursor")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatusIndicator: View {
    let status: KeyboardStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .accessibilityHidden(true)
            Text(status.message)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(status.isError ? Color.orange : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keyboard.status")
    }

    private var iconName: String {
        switch status {
        case .correcting:
            "hourglass"
        case .corrected, .transcriptInserted:
            "checkmark.circle.fill"
        case .ready:
            "star"
        case .fullAccessRequired:
            "lock"
        case .cloudConsentRequired:
            "hand.raised"
        case .noText, .noPendingTranscript, .staleContext, .error:
            "exclamationmark.triangle"
        }
    }
}

private struct LetterKeyboardRows: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 7) {
            CharacterRow(characters: LetterKeys.top, model: model)
            CharacterRow(characters: LetterKeys.middle, model: model)
                .padding(.horizontal, 13)
            HStack(spacing: 5) {
                KeyboardFunctionButton(
                    systemImage: model.shiftState == .uppercase ? "shift.fill" : "shift",
                    accessibilityLabel: model.shiftState == .uppercase ? "Shift on" : "Shift off",
                    action: model.toggleShift
                )
                .accessibilityAddTraits(model.shiftState == .uppercase ? .isSelected : [])

                CharacterRow(characters: LetterKeys.bottom, model: model)

                KeyboardFunctionButton(
                    systemImage: "delete.left",
                    accessibilityLabel: "Delete",
                    action: model.deleteBackward
                )
                .accessibilityIdentifier("keyboard.delete")
            }
        }
    }
}

private struct SymbolKeyboardRows: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 7) {
            CharacterRow(characters: SymbolKeys.top, model: model)
            CharacterRow(characters: SymbolKeys.middle, model: model)
            HStack(spacing: 5) {
                CharacterRow(characters: SymbolKeys.bottom, model: model)

                KeyboardFunctionButton(
                    systemImage: "delete.left",
                    accessibilityLabel: "Delete",
                    action: model.deleteBackward
                )
                .accessibilityIdentifier("keyboard.delete")
            }
        }
    }
}

private struct CharacterRow: View {
    let characters: [KeyboardCharacter]
    let model: KeyboardModel

    var body: some View {
        HStack(spacing: 5) {
            ForEach(characters) { character in
                KeyboardCharacterButton(character: character, model: model)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct KeyboardCharacterButton: View {
    let character: KeyboardCharacter
    let model: KeyboardModel

    var body: some View {
        Button {
            model.insertCharacter(character.output)
        } label: {
            Text(displayedCharacter)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(KeyboardKeyButtonStyle())
        .accessibilityLabel(character.accessibilityLabel)
        .accessibilityIdentifier("keyboard.key.\(character.id)")
    }

    private var displayedCharacter: String {
        guard model.layoutMode == .letters, model.shiftState == .uppercase else {
            return character.output
        }
        return character.output.uppercased()
    }
}

private struct KeyboardControlRow: View {
    let model: KeyboardModel
    let controllerBridge: KeyboardControllerBridge

    var body: some View {
        HStack(spacing: 5) {
            Button(model.layoutMode == .letters ? "123" : "ABC", action: model.toggleLayout)
                .buttonStyle(KeyboardFunctionButtonStyle(width: 54))
                .accessibilityLabel(model.layoutMode == .letters ? "Show numbers and symbols" : "Show letters")
                .accessibilityIdentifier("keyboard.layout")

            NextKeyboardButton(controllerBridge: controllerBridge)
                .frame(width: 44, height: 42)
                .accessibilityIdentifier("keyboard.globe")

            Button(action: model.insertSpace) {
                Text("space")
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(KeyboardKeyButtonStyle())
            .accessibilityIdentifier("keyboard.space")

            Button(action: model.insertReturn) {
                Image(systemName: "return")
                    .frame(width: 48, height: 42)
            }
            .buttonStyle(KeyboardFunctionButtonStyle(width: 54))
            .accessibilityLabel("Return")
            .accessibilityIdentifier("keyboard.return")
        }
    }
}

private struct KeyboardFunctionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(KeyboardFunctionButtonStyle(width: 48))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct KeyboardKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(configuration.isPressed ? Color(uiColor: .systemGray3) : Color(uiColor: .systemBackground))
            .clipShape(.rect(cornerRadius: 6))
            .shadow(color: .black.opacity(0.16), radius: 0.5, y: 1)
    }
}

private struct KeyboardFunctionButtonStyle: ButtonStyle {
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width)
            .foregroundStyle(Color.primary)
            .background(configuration.isPressed ? Color(uiColor: .systemGray2) : Color(uiColor: .systemGray3))
            .clipShape(.rect(cornerRadius: 6))
    }
}

private struct KeyboardAccessoryButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .background(
                isProminent
                    ? Color.accentColor.opacity(configuration.isPressed ? 0.72 : 1)
                    : Color(uiColor: configuration.isPressed ? .systemGray3 : .systemBackground)
            )
            .clipShape(.rect(cornerRadius: 8))
    }
}

private struct KeyboardCharacter: Identifiable, Equatable {
    let id: String
    let output: String
    let accessibilityLabel: String

    init(_ output: String, id: String? = nil, accessibilityLabel: String? = nil) {
        self.id = id ?? output
        self.output = output
        self.accessibilityLabel = accessibilityLabel ?? output
    }
}

private enum LetterKeys {
    static let top = "qwertyuiop".map { KeyboardCharacter(String($0), id: "letter-\($0)") }
    static let middle = "asdfghjkl".map { KeyboardCharacter(String($0), id: "letter-\($0)") }
    static let bottom = "zxcvbnm".map { KeyboardCharacter(String($0), id: "letter-\($0)") }
}

private enum SymbolKeys {
    static let top = "1234567890".map { KeyboardCharacter(String($0), id: "symbol-\($0)") }
    static let middle = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
        .enumerated()
        .map { KeyboardCharacter($0.element, id: "symbol-middle-\($0.offset)") }
    static let bottom = [".", ",", "?", "!", "'", "[", "]", "_"]
        .enumerated()
        .map { KeyboardCharacter($0.element, id: "symbol-bottom-\($0.offset)") }
}
