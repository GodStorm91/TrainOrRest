import SwiftUI
import UIKit

/// Small purple-gradient sparkle avatar for the coach, reused in the chat
/// header and beside assistant bubbles.
struct CoachAvatar: View {
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Theme.accent, Theme.accent2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.accentSoft, radius: size * 0.35)
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    @State private var showsGroundingSummary = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if isUser {
                Spacer(minLength: 40)
            } else {
                CoachAvatar(size: 26)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                messageBody
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(bubbleShape.fill(isUser ? Theme.accent : Theme.card))
                    .overlay { if !isUser { bubbleShape.strokeBorder(Theme.border, lineWidth: 1) } }
                CopyMessageButton(text: message.text)
                if let applied = message.appliedAdjustment {
                    appliedBadge(applied)
                        .padding(.top, 1)
                }
                if !isUser, let footnote = message.groundingFootnote, let summary = message.groundingSummary {
                    groundingFootnote(footnote, summary: summary)
                }
            }
            if !isUser {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .sheet(isPresented: $showsGroundingSummary) {
            ReceiptSheet(
                title: "Evidence",
                subtitle: message.groundingFootnote,
                rows: [
                    .detail("Grounding summary", value: message.groundingSummary ?? "", symbol: "doc.text.magnifyingglass")
                ]
            )
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        // AI: 18/18/18/5 · User: 18/18/5/18 (top-leading, top-trailing, bottom-trailing, bottom-leading)
        UnevenRoundedRectangle(
            cornerRadii: isUser
                ? .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 5, topTrailing: 18)
                : .init(topLeading: 18, bottomLeading: 5, bottomTrailing: 18, topTrailing: 18),
            style: .continuous
        )
    }

    @ViewBuilder
    private var messageBody: some View {
        if isUser {
            MarkdownMessageView(text: message.text, tone: .onAccent, allowsRuleTokens: false)
        } else {
            MarkdownMessageView(text: message.text, tone: .standard, allowsRuleTokens: true)
                .textSelection(.enabled)
        }
    }

    /// Copies the message verbatim (markdown included) and confirms briefly.
    private struct CopyMessageButton: View {
        let text: String

        @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
        @State private var didCopy = false
        @State private var resetTask: Task<Void, Never>?

        private static let confirmationSeconds: Double = 1.6

        private var language: CoachLanguage {
            CoachLanguage(rawValue: languageRaw) ?? .en
        }

        var body: some View {
            Button(action: copy) {
                HStack(spacing: 5) {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(didCopy ? Theme.good : Theme.faint)
                    Text(didCopy ? language.copiedLabel : language.copyLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: didCopy)
            .accessibilityLabel(didCopy ? language.copiedLabel : language.copyLabel)
            .onDisappear { resetTask?.cancel() }
        }

        private func copy() {
            UIPasteboard.general.string = text
            didCopy = true
            // Restart the countdown so a re-tap never leaves a stale checkmark.
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(Self.confirmationSeconds))
                guard !Task.isCancelled else { return }
                // Task.sleep resumes off the main actor; hop back before touching state.
                await MainActor.run { didCopy = false }
            }
        }
    }

    private func appliedBadge(_ applied: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Validated plan update", systemImage: "checkmark.shield.fill")
                .font(.caption.weight(.semibold))
            Text(applied)
                .font(.caption)
        }
        .foregroundStyle(Theme.good)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.soft(Theme.good), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.good.opacity(0.3), lineWidth: 1)
        )
    }

    private func groundingFootnote(_ footnote: String, summary: String) -> some View {
        Button {
            showsGroundingSummary = true
        } label: {
            Label {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review evidence. \(footnote)")
    }
}
