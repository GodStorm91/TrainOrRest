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
    var hidesSources: Bool = false
    var showsAvatar: Bool = true
    var showsSource: Bool = true
    var isGroupedWithPrevious: Bool = false

    @State private var showsGroundingSummary = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if isUser {
                Spacer(minLength: 40)
            } else if showsAvatar {
                CoachAvatar(size: 26)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 26, height: 26)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                messageBody
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(bubbleShape.fill(isUser ? Theme.accent : Theme.card))
                    .overlay { if !isUser { bubbleShape.strokeBorder(Theme.border, lineWidth: 1) } }
                    .shadow(color: isUser ? .clear : Color.black.opacity(0.045), radius: 10, x: 0, y: 4)

                if let applied = message.appliedAdjustment, !message.text.hasPrefix("Applied:") {
                    appliedBadge(applied)
                        .padding(.top, 1)
                }

                if showsSource, !hidesSources, !isUser, let footnote = message.groundingFootnote, let summary = message.groundingSummary {
                    groundingFootnote(footnote, summary: summary)
                        .padding(.top, 2)
                }
            }

            if !isUser {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.top, isGroupedWithPrevious ? -8 : 0)
        .contextMenu {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                UIPasteboard.general.string = displayText
            } label: {
                Label("Sao chép", systemImage: "doc.on.doc")
            }
            .accessibilityLabel("Sao chép")

            if !isUser {
                Button {} label: { Label("Hữu ích", systemImage: "hand.thumbsup") }
                    .accessibilityLabel("Hữu ích")
                Button {} label: { Label("Không hữu ích", systemImage: "hand.thumbsdown") }
                    .accessibilityLabel("Không hữu ích")
                Button(role: .destructive) {} label: { Label("Báo lỗi", systemImage: "exclamationmark.bubble") }
                    .accessibilityLabel("Báo lỗi")
            }
        }
        .sheet(isPresented: $showsGroundingSummary) {
            ReceiptSheet(
                title: "Nguồn dữ liệu đã sử dụng",
                subtitle: sourceLine(for: message.groundingFootnote),
                rows: sourceRows(summary: message.groundingSummary ?? "")
            )
        }
    }

    private var displayText: String {
        if isUser {
            return message.text.components(separatedBy: "\n\nAttached:").first ?? message.text
        }
        return message.text
    }

    private var bubbleShape: UnevenRoundedRectangle {
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
            MarkdownMessageView(text: displayText, tone: .onAccent, allowsRuleTokens: false)
        } else {
            MarkdownMessageView(text: displayText, tone: .standard, allowsRuleTokens: true)
                .textSelection(.enabled)
        }
    }

    private func appliedBadge(_ applied: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Đã kiểm tra và cập nhật kế hoạch", systemImage: "checkmark.shield.fill")
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
            Text(sourceLine(for: footnote))
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Xem nguồn dữ liệu")
    }

    private func sourceLine(for footnote: String?) -> String {
        let footnote = footnote ?? ""
        let sourceCount = max(1, footnote.components(separatedBy: " · ").dropFirst().filter { !$0.isEmpty && $0 != "No evidence" }.count)
        if let time = footnote.components(separatedBy: " · ").first?.replacingOccurrences(of: "Based on ", with: ""), !time.isEmpty {
            return "Dựa trên dữ liệu lúc \(time) · Xem nguồn"
        }
        return "Dựa trên \(sourceCount) nguồn dữ liệu · Xem nguồn"
    }

    private func sourceRows(summary: String) -> [ReceiptSheet.Row] {
        let lines = summary
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if lines.isEmpty {
            return [.check("Đã kiểm tra dữ liệu", value: "Không có chi tiết nguồn bổ sung.")]
        }
        return lines.prefix(6).map { line in
            .check(sourceTitle(for: line), value: line)
        }
    }

    private func sourceTitle(for line: String) -> String {
        if line.localizedCaseInsensitiveContains("readiness") { return "Thể trạng hiện tại" }
        if line.localizedCaseInsensitiveContains("plan") { return "Kế hoạch tuần này" }
        if line.localizedCaseInsensitiveContains("workout") { return "Buổi tập gần nhất" }
        if line.localizedCaseInsensitiveContains("photo") { return "Ảnh đính kèm" }
        return "Nguồn dữ liệu"
    }
}
