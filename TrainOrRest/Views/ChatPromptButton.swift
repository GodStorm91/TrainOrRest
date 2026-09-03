import SwiftUI

struct ChatPromptButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                horizontalPromptContent
                    .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        promptIcon
                        promptTitle
                    }
                    promptChevron
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
            .torGlass(cornerRadius: 17, tint: .subtle)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var horizontalPromptContent: some View {
        HStack(spacing: 12) {
            promptIcon
            promptTitle
            promptChevron
        }
    }

    @ViewBuilder
    private var promptIcon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accent.opacity(0.12), in: Circle())
        }
    }

    private var promptTitle: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var promptChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.faint)
    }
}
