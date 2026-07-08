import SwiftUI

struct ContextChip: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ContextChipLabel(title: title, detail: detail, systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct ContextChipLabel: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Theme.accent.opacity(0.8) : Theme.faint)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(isSelected ? Theme.accent : Theme.text)
        .background(
            isSelected ? Theme.accentSoft : Theme.chip,
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(isSelected ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
        )
    }
}
