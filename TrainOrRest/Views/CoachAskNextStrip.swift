import SwiftUI

/// The contextual "Ask Next" suggestion strip that sits above the composer:
/// one scrollable row of quick prompts, the first highlighted as the primary
/// suggestion. Tapping a chip hands its text back to the composer.
struct CoachAskNextStrip: View {
    let prompts: [String]
    var label: String = "ASK NEXT"
    let onTap: (String) -> Void

    var body: some View {
        if !prompts.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                    Text(label)
                        .font(.torLabel(10, .bold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(prompts.enumerated()), id: \.element) { index, prompt in
                            chip(prompt, primary: index == 0)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func chip(_ text: String, primary: Bool) -> some View {
        Button { onTap(text) } label: {
            Text(text)
                .font(.system(size: 13, weight: primary ? .semibold : .medium))
                .foregroundStyle(primary ? Theme.accent : Theme.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    primary ? Theme.accentSoft : Theme.card,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(primary ? Theme.accent : Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
