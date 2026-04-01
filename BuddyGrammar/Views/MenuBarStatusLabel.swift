import SwiftUI

struct MenuBarStatusLabel: View {
    @Bindable var status: MenuBarStatusModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.phase.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)

            if !status.phase.title.isEmpty {
                Text(status.phase.title)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.phase.accessibilityLabel)
    }

    private var iconColor: Color {
        switch status.phase {
        case .success:
            .green
        case .failure:
            .orange
        default:
            .primary
        }
    }
}
