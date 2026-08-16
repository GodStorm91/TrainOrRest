import SwiftUI

struct ChatPromptButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                }

                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.faint)
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
            .torGlass(cornerRadius: 17, tint: .subtle)
        }
        .buttonStyle(.plain)
    }
}
