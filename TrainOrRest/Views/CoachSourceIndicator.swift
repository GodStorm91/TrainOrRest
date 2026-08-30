import SwiftUI

struct CoachSourceIndicator: View {
    let count: Int
    let language: CoachLanguage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "paperclip")
                    .font(.caption.weight(.semibold))
                Text(language.contextSourceCountLabel(count: count))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.chip, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Capsule())
        .accessibilityLabel(language.contextSourceCountLabel(count: count))
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    CoachSourceIndicator(count: 2, language: .vi, onTap: {})
        .padding()
        .background(Theme.bg)
}
