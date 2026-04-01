import SwiftUI

// MARK: - Neobrutalist Theme

enum NeoTheme {
    static let background = Color(hex: 0xEFF1F5)
    static let foreground = Color(hex: 0x4C4F69)
    static let card = Color.white
    static let primary = Color(hex: 0x8839EF)
    static let accent = Color(hex: 0x04A5E5)
    static let destructive = Color(hex: 0xD20F39)
    static let muted = Color(hex: 0xDCE0E8)
    static let mutedForeground = Color(hex: 0x6C6F85)
    static let border = Color(hex: 0xBCC0CC)
    static let green = Color(hex: 0x40A02B)
    static let orange = Color(hex: 0xFE640B)

    static let shadow = Color(hex: 0x1A1A2E)
    static let borderWidth: CGFloat = 2
    static let shadowOffset: CGFloat = 4
    static let cornerRadius: CGFloat = 6
}

// MARK: - Color Hex Init

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Neobrutalist Card

struct NeoBrutalistCard: ViewModifier {
    var filled: Bool = true

    func body(content: Content) -> some View {
        content
            .background(filled ? NeoTheme.card : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                    .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
            )
            .shadow(color: NeoTheme.shadow.opacity(0.18), radius: 0, x: NeoTheme.shadowOffset, y: NeoTheme.shadowOffset)
    }
}

// MARK: - Neobrutalist Button

struct NeoBrutalistButton: ButtonStyle {
    var isPrimary: Bool = true
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(isPrimary ? Color.white : NeoTheme.foreground)
            .background(isPrimary ? NeoTheme.primary : NeoTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: NeoTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: NeoTheme.cornerRadius)
                    .stroke(NeoTheme.foreground, lineWidth: NeoTheme.borderWidth)
            )
            .shadow(
                color: NeoTheme.shadow.opacity(0.18),
                radius: 0,
                x: configuration.isPressed ? 0 : 3,
                y: configuration.isPressed ? 0 : 3
            )
            .offset(
                x: configuration.isPressed ? 3 : 0,
                y: configuration.isPressed ? 3 : 0
            )
            .opacity(isDisabled ? 0.5 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
