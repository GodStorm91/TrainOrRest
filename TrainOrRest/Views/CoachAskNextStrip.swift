import SwiftUI

/// The contextual "Ask Next" suggestion strip that sits above the composer.
/// P1 keeps it quiet: at most two full-width rows, no horizontal clipping.
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

                VStack(spacing: 8) {
                    ForEach(Array(prompts.prefix(2).enumerated()), id: \.element) { index, prompt in
                        chip(prompt, primary: index == 0)
                    }
                }
            }
        }
    }

    private func chip(_ text: String, primary: Bool) -> some View {
        Button { onTap(text) } label: {
            Text(text)
                .font(.system(size: 13, weight: primary ? .semibold : .medium))
                .foregroundStyle(primary ? Theme.accent : Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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
        .accessibilityLabel(text)
    }
}
