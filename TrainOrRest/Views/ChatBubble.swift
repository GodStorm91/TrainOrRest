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
    var language: CoachLanguage = .current
    var onRetry: (ChatMessage) -> Void = { _ in }
    var onDismissFailure: (ChatMessage) -> Void = { _ in }
    var onCancelRetry: (ChatMessage) -> Void = { _ in }
    var actionableInteractionID: String?
    var isSubmittingInteraction = false
    var onSelectInteractionOption: (ChatMessage, CoachChoiceOption) -> Void = { _, _ in }
    var onSelectInteractionOther: (ChatMessage, CoachResponseInteraction) -> Void = { _, _ in }

    @State private var showsGroundingSummary = false

    private var isUser: Bool { message.role == .user }
    private var hasVisibleAssistantText: Bool {
        !isUser && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var showsInlineFailureState: Bool {
        !isUser && [.failed, .retrying, .reconciling].contains(message.assistantStatus)
    }

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
                if isUser || hasVisibleAssistantText {
                    messageBody
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(bubbleShape.fill(isUser ? Theme.accent : Theme.card))
                        .overlay { if !isUser { bubbleShape.strokeBorder(Theme.border, lineWidth: 1) } }
                        .shadow(color: isUser ? .clear : Color.black.opacity(0.045), radius: 10, x: 0, y: 4)
                }

                if message.isIncomplete && hasVisibleAssistantText {
                    Label(language.incompleteResponseLabel, systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                        .padding(.top, 2)
                        .accessibilityLabel(language.incompleteResponseLabel)
                }

                if showsInlineFailureState {
                    CoachInlineFailureCard(
                        message: message,
                        language: language,
                        onRetry: { onRetry(message) },
                        onDismiss: { onDismissFailure(message) },
                        onCancel: { onCancelRetry(message) }
                    )
                    .padding(.top, hasVisibleAssistantText ? 6 : 0)
                }

                if let applied = message.appliedAdjustment, !message.text.hasPrefix("Applied:") {
                    appliedBadge(applied)
                        .padding(.top, 1)
                }

                if !isUser, let interaction = message.interaction {
                    CoachResponseInteractionView(
                        interaction: interaction,
                        language: language,
                        isActionable: interaction.id == actionableInteractionID,
                        isSubmitting: isSubmittingInteraction,
                        onSelect: { option in onSelectInteractionOption(message, option) },
                        onOther: { onSelectInteractionOther(message, interaction) }
                    )
                    .padding(.top, hasVisibleAssistantText ? 6 : 0)
                }

                if showsSource, !hidesSources, !isUser, message.assistantStatus == .completed, let footnote = message.groundingFootnote, let summary = message.groundingSummary {
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
        .onAppear {
            announceInlineFailureIfNeeded()
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

    private func announceInlineFailureIfNeeded() {
        guard showsInlineFailureState, !message.announcedFailure else { return }
        message.announcedFailure = true
        UIAccessibility.post(
            notification: .announcement,
            argument: message.assistantStatus == .retrying ? language.retryingInlineTitle : language.interruptedFailureTitle
        )
    }
}

struct CoachResponseInteractionView: View {
    let interaction: CoachResponseInteraction
    let language: CoachLanguage
    let isActionable: Bool
    let isSubmitting: Bool
    let onSelect: (CoachChoiceOption) -> Void
    let onOther: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if interaction.status == .resolved {
                resolvedBadge
            } else if isActionable {
                pendingChoices
            } else {
                inactivePendingBadge
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var pendingChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(interaction.title ?? language.choiceDefaultTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 4)

            ForEach(interaction.options) { option in
                CoachChoiceOptionCard(
                    option: option,
                    language: language,
                    isDisabled: isSubmitting,
                    onSelect: { onSelect(option) }
                )
            }

            if interaction.allowOther {
                Button(action: onOther) {
                    HStack(spacing: 10) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text(interaction.otherLabel ?? language.choiceOtherLabel)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "keyboard")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.faint)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .accessibilityLabel(interaction.otherLabel ?? language.choiceOtherLabel)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private var resolvedBadge: some View {
        Text(interaction.resolvedSummary(language: language))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
            )
            .accessibilityLabel(interaction.resolvedSummary(language: language))
            .accessibilityValue(language.choiceSelectedAccessibilitySuffix)
    }

    private var inactivePendingBadge: some View {
        Text(interaction.title ?? language.choiceDefaultTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .accessibilityLabel(interaction.title ?? language.choiceDefaultTitle)
            .accessibilityValue(language.choiceDisabledAccessibilitySuffix)
    }
}

private struct CoachChoiceOptionCard: View {
    let option: CoachChoiceOption
    let language: CoachLanguage
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.label)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: option.description == nil ? 56 : 76, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isDisabled ? 0.56 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isDisabled ? language.choiceDisabledAccessibilitySuffix : "")
    }

    private var accessibilityLabel: String {
        [option.label, option.description].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        .joined(separator: ", ")
    }
}

private struct CoachInlineFailureCard: View {
    let message: ChatMessage
    let language: CoachLanguage
    let onRetry: () -> Void
    let onDismiss: () -> Void
    let onCancel: () -> Void

    private var category: CoachErrorCategory {
        message.errorCategory ?? .retryableResponse
    }

    private var title: String {
        if message.assistantStatus == .retrying { return language.retryingInlineTitle }
        if message.assistantStatus == .reconciling { return language.mutationReconciliationTitle }
        if category == .missingAttachment { return language.missingAttachmentFailureTitle }
        return language.interruptedFailureTitle
    }

    private var bodyText: String {
        if message.assistantStatus == .retrying { return language.retryingInlineMessage }
        if message.assistantStatus == .reconciling { return language.mutationReconciliationMessage }
        return message.errorMessage ?? language.interruptedFailureMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(bodyText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                if message.assistantStatus == .retrying {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    inlineButton(language.cancelRetryLabel, role: .secondary, action: onCancel)
                        .accessibilityLabel("Hủy thử lại")
                } else if message.assistantStatus == .reconciling || category == .mutationUnknown {
                    Spacer(minLength: 0)
                    inlineButton(language.checkStatusLabel, role: .primary, action: {})
                        .accessibilityLabel("Kiểm tra trạng thái cập nhật")
                } else if category == .missingAttachment {
                    inlineButton(language.dismissInlineErrorLabel, role: .secondary, action: onDismiss)
                    Spacer(minLength: 0)
                    inlineButton(language.chooseDataAgainLabel, role: .primary, action: {})
                } else if category == .authentication {
                    inlineButton(language.dismissInlineErrorLabel, role: .secondary, action: onDismiss)
                    Spacer(minLength: 0)
                    inlineButton(language.checkConnectionLabel, role: .primary, action: {})
                } else {
                    inlineButton(language.dismissInlineErrorLabel, role: .secondary, action: onDismiss)
                        .accessibilityLabel("Bỏ qua lỗi phản hồi")
                    Spacer(minLength: 0)
                    inlineButton(language.retryLabel, role: .primary, action: onRetry)
                        .accessibilityLabel("Thử lại phản hồi")
                }
            }
            .frame(minHeight: 44)
        }
        .padding(12)
        .frame(maxWidth: 310, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Phản hồi của Coach bị gián đoạn")
    }

    private func inlineButton(_ title: String, role: ButtonRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(role == .primary ? accent : Theme.dim)
                .frame(minHeight: 44)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch message.assistantStatus {
        case .retrying:
            return "arrow.triangle.2.circlepath"
        case .reconciling:
            return "checkmark.shield"
        default:
            return "exclamationmark.triangle.fill"
        }
    }

    private var accent: Color {
        category == .mutationUnknown ? Theme.warn : Theme.bad
    }

    private var surface: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: 0x252228).withAlphaComponent(0.98)
                : UIColor(hex: 0xFFF7F2).withAlphaComponent(0.99)
        })
    }

    private enum ButtonRole {
        case primary, secondary
    }
}

#Preview("Coach choice pending") {
    CoachResponseInteractionView(
        interaction: .preview(status: .pending),
        language: .vi,
        isActionable: true,
        isSubmitting: false,
        onSelect: { _ in },
        onOther: {}
    )
    .padding()
    .background(Theme.bg)
}

#Preview("Coach choice selected") {
    CoachResponseInteractionView(
        interaction: .preview(status: .resolved, selectedOptionId: "adjust_plan"),
        language: .vi,
        isActionable: false,
        isSubmitting: false,
        onSelect: { _ in },
        onOther: {}
    )
    .padding()
    .background(Theme.bg)
}

#Preview("Coach choice other") {
    CoachResponseInteractionView(
        interaction: .preview(status: .resolved, resolvedWithOther: true),
        language: .vi,
        isActionable: false,
        isSubmitting: false,
        onSelect: { _ in },
        onOther: {}
    )
    .padding()
    .background(Theme.bg)
}

private extension CoachResponseInteraction {
    static func preview(
        status: CoachResponseInteractionStatus,
        selectedOptionId: String? = nil,
        resolvedWithOther: Bool = false
    ) -> CoachResponseInteraction {
        CoachResponseInteraction(
            id: "post_run_next_step",
            type: .singleChoice,
            title: "Chọn bước tiếp theo",
            options: [
                CoachChoiceOption(
                    id: "keep_plan",
                    label: "Giữ nguyên kế hoạch",
                    description: "Không thay đổi các buổi tập sắp tới",
                    value: "Giữ nguyên kế hoạch hiện tại."
                ),
                CoachChoiceOption(
                    id: "adjust_plan",
                    label: "Xem đề xuất điều chỉnh",
                    description: "Coach đề xuất thay đổi dựa trên buổi chạy này",
                    value: "Hãy đề xuất cách điều chỉnh các buổi tập tiếp theo."
                )
            ],
            allowOther: true,
            otherLabel: "Yêu cầu khác…",
            otherPlaceholder: "Bạn muốn Coach điều chỉnh như thế nào?",
            status: status,
            selectedOptionId: selectedOptionId,
            resolvedWithOther: resolvedWithOther
        )
    }
}
