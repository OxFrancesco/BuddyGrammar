import SwiftUI

struct LatexKey: Identifiable, Equatable {
    let display: String
    let command: String

    var id: String { command }
}

enum LatexKeys {
    static let rows: [[LatexKey]] = [
        [
            LatexKey(display: "⁄", command: "\\frac{}{}"),
            LatexKey(display: "√", command: "\\sqrt{}"),
            LatexKey(display: "xⁿ", command: "^{}"),
            LatexKey(display: "xₙ", command: "_{}"),
            LatexKey(display: "∑", command: "\\sum"),
            LatexKey(display: "∫", command: "\\int"),
            LatexKey(display: "∏", command: "\\prod"),
            LatexKey(display: "lim", command: "\\lim"),
        ],
        [
            LatexKey(display: "α", command: "\\alpha"),
            LatexKey(display: "β", command: "\\beta"),
            LatexKey(display: "γ", command: "\\gamma"),
            LatexKey(display: "δ", command: "\\delta"),
            LatexKey(display: "θ", command: "\\theta"),
            LatexKey(display: "λ", command: "\\lambda"),
            LatexKey(display: "μ", command: "\\mu"),
            LatexKey(display: "π", command: "\\pi"),
            LatexKey(display: "σ", command: "\\sigma"),
            LatexKey(display: "ω", command: "\\omega"),
        ],
        [
            LatexKey(display: "≤", command: "\\leq"),
            LatexKey(display: "≥", command: "\\geq"),
            LatexKey(display: "≠", command: "\\neq"),
            LatexKey(display: "≈", command: "\\approx"),
            LatexKey(display: "×", command: "\\times"),
            LatexKey(display: "⋅", command: "\\cdot"),
            LatexKey(display: "±", command: "\\pm"),
            LatexKey(display: "∞", command: "\\infty"),
            LatexKey(display: "→", command: "\\rightarrow"),
        ],
        [
            LatexKey(display: "sin", command: "\\sin"),
            LatexKey(display: "cos", command: "\\cos"),
            LatexKey(display: "tan", command: "\\tan"),
            LatexKey(display: "log", command: "\\log"),
            LatexKey(display: "ln", command: "\\ln"),
            LatexKey(display: "exp", command: "\\exp"),
        ],
    ]
}

struct LatexKeyboardLayer: View {
    let model: KeyboardModel
    let metrics: KeyboardMetrics

    private var rowHeight: CGFloat {
        max(28, (metrics.bodyHeight - 4 * metrics.rowSpacing) / 5)
    }

    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            ForEach(0..<LatexKeys.rows.count, id: \.self) { index in
                HStack(spacing: metrics.keySpacing) {
                    ForEach(LatexKeys.rows[index]) { key in
                        LatexKeyButton(key: key, model: model, height: rowHeight)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: metrics.keySpacing) {
                Button("ABC") {
                    model.setLayout(.letters)
                }
                .font(.callout)
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth * 1.2, height: rowHeight)
                )
                .accessibilityLabel("Show letters")
                .accessibilityIdentifier("keyboard.layout")

                Button(action: model.insertSpace) {
                    Text("space")
                        .font(.callout)
                        .frame(maxWidth: .infinity, minHeight: rowHeight)
                }
                .buttonStyle(KeyboardKeyButtonStyle())
                .accessibilityIdentifier("keyboard.space")

                Button(action: model.deleteBackward) {
                    Image(systemName: "delete.left")
                        .frame(width: metrics.wideFunctionKeyWidth, height: rowHeight)
                }
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth, height: rowHeight)
                )
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("keyboard.delete")

                Button(action: model.insertReturn) {
                    Image(systemName: "return")
                        .frame(width: metrics.wideFunctionKeyWidth * 1.2, height: rowHeight)
                }
                .buttonStyle(
                    KeyboardFunctionButtonStyle(width: metrics.wideFunctionKeyWidth * 1.2, height: rowHeight)
                )
                .accessibilityLabel("Return")
                .accessibilityIdentifier("keyboard.return")
            }
        }
    }
}

private struct LatexKeyButton: View {
    let key: LatexKey
    let model: KeyboardModel
    let height: CGFloat

    var body: some View {
        Button {
            model.insertCharacter(key.command)
        } label: {
            VStack(spacing: 1) {
                Text(key.display)
                    .font(.callout)
                Text(key.command)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, minHeight: height)
        }
        .buttonStyle(KeyboardKeyButtonStyle())
        .accessibilityLabel(key.command)
        .accessibilityIdentifier("keyboard.latex.\(key.command)")
    }
}
