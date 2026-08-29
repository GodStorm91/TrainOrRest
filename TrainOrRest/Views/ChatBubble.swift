import SwiftUI
import UIKit

/// Neutral provenance mark for the coach, reused in the chat header and beside
/// assistant bubbles.
struct CoachAvatar: View {
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(Theme.card)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            .overlay {
                Image(systemName: "figure.run")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
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
    var onCheckStatus: () -> Void = {}
    var onChooseDataAgain: (ChatMessage) -> Void = { _ in }
    var onCheckConnection: () -> Void = {}
    var actionableInteractionID: String?
    var isSubmittingInteraction = false
    var processingStage: CoachProcessingStage?
    var onSelectInteractionOption: (ChatMessage, CoachChoiceOption) -> Void = { _, _ in }
    var onSelectInteractionOther: (ChatMessage, CoachResponseInteraction) -> Void = { _, _ in }

    @State private var showsGroundingSummary = false

    private var isUser: Bool { message.role == .user }
    private var hasVisibleAssistantText: Bool {
        !isUser && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var showsProcessingState: Bool {
        !isUser && !hasVisibleAssistantText && [.queued, .streaming].contains(message.assistantStatus)
    }
    private var showsInlineFailureState: Bool {
        !isUser && [.failed, .retrying, .reconciling].contains(message.assistantStatus)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if isUser {
                Spacer(minLength: 40)
            } else if showsAvatar && !showsProcessingState {
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

                if isUser, !message.contextItems.isEmpty {
                    CoachContextChipRow(items: message.contextItems)
                        .padding(.top, 2)
                }

                if showsProcessingState {
                    CoachProcessingRow(
                        label: language.processingLabel(for: processingStage),
                        petState: CoachPetBehavior.processingState(for: processingStage),
                        reduceMotion: UIAccessibility.isReduceMotionEnabled
                    )
                    .padding(.top, 2)
                    .transition(.opacity)
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
                        onCancel: { onCancelRetry(message) },
                        onCheckStatus: onCheckStatus,
                        onChooseDataAgain: { onChooseDataAgain(message) },
                        onCheckConnection: onCheckConnection
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
                Label(language.copyLabel, systemImage: "doc.on.doc")
            }
            .accessibilityLabel(language.copyLabel)

        }
        .sheet(isPresented: $showsGroundingSummary) {
            ReceiptSheet(
                title: language.dataSourcesUsedTitle,
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
            CoachProgressiveResponseView(text: displayText, language: language)
                .textSelection(.enabled)
        }
    }

    private func appliedBadge(_ applied: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(language.verifiedPlanUpdateLabel, systemImage: "checkmark.shield.fill")
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
        .accessibilityLabel(language.viewSourcesLabel)
    }

    private func sourceLine(for footnote: String?) -> String {
        let footnote = footnote ?? ""
        let sourceCount = max(1, footnote.components(separatedBy: " · ").dropFirst().filter { !$0.isEmpty && $0 != "No evidence" }.count)
        if let time = footnote.components(separatedBy: " · ").first?.replacingOccurrences(of: "Based on ", with: ""), !time.isEmpty {
            return language.sourceLineWithTime(time)
        }
        return language.sourceLineWithCount(sourceCount)
    }

    private func sourceRows(summary: String) -> [ReceiptSheet.Row] {
        let lines = summary
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if lines.isEmpty {
            return [.check(language.checkedDataRowTitle, value: language.noAdditionalSourceDetail)]
        }
        return lines.prefix(6).map { line in
            .check(sourceTitle(for: line), value: line)
        }
    }

    private func sourceTitle(for line: String) -> String {
        if line.localizedCaseInsensitiveContains("readiness") { return language.readinessSourceTitle }
        if line.localizedCaseInsensitiveContains("plan") { return language.planSourceTitle }
        if line.localizedCaseInsensitiveContains("workout") { return language.latestWorkoutChipLabel }
        if line.localizedCaseInsensitiveContains("photo") { return language.photoSourceTitle }
        return language.genericSourceTitle
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

private struct CoachProgressiveResponseView: View {
    let text: String
    let language: CoachLanguage
    @State private var isExpanded = false

    private var presentation: Presentation {
        Presentation(text: text)
    }

    var body: some View {
        if presentation.shouldCollapse {
            VStack(alignment: .leading, spacing: 10) {
                MarkdownMessageView(text: presentation.visibleText, tone: .standard, allowsRuleTokens: true)
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? language.collapseDetailsLabel : language.expandDetailsLabel)
                            .font(.caption.weight(.bold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? language.collapseDetailsLabel : language.expandDetailsLabel)
                .accessibilityValue(isExpanded ? language.collapseDetailsLabel : language.expandDetailsLabel)

                if isExpanded {
                    MarkdownMessageView(text: presentation.detailText, tone: .standard, allowsRuleTokens: true)
                        .transition(.opacity)
                }
            }
        } else {
            MarkdownMessageView(text: text, tone: .standard, allowsRuleTokens: true)
        }
    }

    private struct Presentation {
        let visibleText: String
        let detailText: String
        let shouldCollapse: Bool

        init(text: String) {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = normalized
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let nonEmpty = lines.filter { !$0.isEmpty }
            let bulletLines = nonEmpty.filter { $0.hasPrefix("- ") || $0.hasPrefix("• ") }
            let cutoff = min(nonEmpty.count, bulletLines.count >= 4 ? 5 : 7)
            self.shouldCollapse = normalized.count > 900 || nonEmpty.count > 10 || bulletLines.count >= 4
            if shouldCollapse, cutoff < nonEmpty.count {
                self.visibleText = nonEmpty.prefix(cutoff).joined(separator: "\n")
                self.detailText = nonEmpty.dropFirst(cutoff).joined(separator: "\n")
            } else {
                self.visibleText = normalized
                self.detailText = ""
            }
        }
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

private struct CoachContextChipRow: View {
    let items: [CoachContextItem]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    Image(systemName: symbol(for: item.type))
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(item.label)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .background(Theme.chip, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                .accessibilityLabel(item.label)
            }
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }

    private func symbol(for type: CoachContextItem.Kind) -> String {
        switch type {
        case .raceGoal:
            return "flag.checkered"
        case .remainingPlan, .trainingPlan:
            return "calendar"
        case .healthData:
            return "heart"
        case .workout, .completedRun:
            return "figure.run"
        case .planAssessment:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

enum CoachPetState: String, Equatable {
    case hidden
    case idle
    case preparing
    case analyzing
    case buildingRecommendation
    case streaming
    case success
    case error
    case cancelled
}

enum CoachPetBehavior {
    static let revealDelay: TimeInterval = 0.45
    static let celebrationDuration: TimeInterval = 0.65

    static func processingState(for stage: CoachProcessingStage?) -> CoachPetState {
        guard let stage else { return .idle }
        switch stage {
        case .preparingContext:
            return .preparing
        case .readingTrainingPlan, .comparingWithGoal, .checkingTrainingLoad, .checkingRecovery, .reviewingUpcomingWorkouts:
            return .analyzing
        case .buildingRecommendation, .finalizing:
            return .buildingRecommendation
        }
    }

    static func state(for generationState: CoachGenerationState) -> CoachPetState {
        switch generationState {
        case .idle:
            return .hidden
        case .sending:
            return .preparing
        case .processing(_, let stage):
            return processingState(for: stage)
        case .streaming:
            return .streaming
        case .awaitingChoice, .completed:
            return .success
        case .failed:
            return .error
        case .cancelled:
            return .cancelled
        }
    }

    static func shouldReveal(startedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(startedAt) >= revealDelay
    }

    static func isLooping(_ state: CoachPetState) -> Bool {
        switch state {
        case .preparing, .analyzing, .buildingRecommendation:
            return true
        case .hidden, .idle, .streaming, .success, .error, .cancelled:
            return false
        }
    }
}

private struct CoachProcessingRow: View {
    let label: String
    let petState: CoachPetState
    let reduceMotion: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasPassedPetDelay = false
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 9) {
            CoachPetSlot(
                state: hasPassedPetDelay ? petState : .hidden,
                reduceMotion: reduceMotion,
                isActive: scenePhase == .active
            )
            .accessibilityHidden(true)
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !reduceMotion && !hasPassedPetDelay {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 330, minHeight: 58, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .opacity(reduceMotion ? 1 : (isPulsing ? 0.74 : 1))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            UIAccessibility.post(notification: .announcement, argument: label)
        }
        .task {
            hasPassedPetDelay = false
            try? await Task.sleep(nanoseconds: UInt64(CoachPetBehavior.revealDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                hasPassedPetDelay = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

private struct CoachPetSlot: View {
    let state: CoachPetState
    let reduceMotion: Bool
    let isActive: Bool

    var body: some View {
        ZStack {
            if state == .hidden {
                Image(systemName: "sparkle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)
                    .background(Theme.accentSoft, in: Circle())
            } else {
                CoachPetView(state: state, reduceMotion: reduceMotion, isActive: isActive)
                    .transition(.opacity)
            }
        }
        .frame(width: 42, height: 42)
        .background(Theme.soft(Theme.accent, 0.08), in: Circle())
    }
}

struct CoachPetView: View {
    let state: CoachPetState
    let reduceMotion: Bool
    let isActive: Bool
    @State private var loop = false

    private var shouldAnimate: Bool {
        isActive && !reduceMotion && CoachPetBehavior.isLooping(state)
    }

    var body: some View {
        ZStack {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .scaleEffect(scale)
                .offset(x: horizontalOffset, y: bodyOffset)
                .rotationEffect(.degrees(rotationAngle))
                .opacity(state == .cancelled ? 0.72 : 1)

            stateOverlay
        }
        .frame(width: 42, height: 42)
        .onAppear { startAnimationIfNeeded() }
        .onChange(of: state) { _, _ in startAnimationIfNeeded() }
        .onChange(of: reduceMotion) { _, _ in startAnimationIfNeeded() }
        .onChange(of: isActive) { _, _ in startAnimationIfNeeded() }
    }

    private var assetName: String {
        switch state {
        case .hidden, .idle, .cancelled:
            return "coach-pet-idle"
        case .preparing:
            return "coach-pet-breathing"
        case .analyzing:
            return "coach-pet-analyzing"
        case .buildingRecommendation:
            return "coach-pet-building"
        case .streaming:
            return "coach-pet-jog"
        case .success:
            return "coach-pet-success"
        case .error:
            return "coach-pet-breathing"
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch state {
        case .preparing:
            Circle()
                .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1.3)
                .frame(width: 8, height: 8)
                .offset(x: -14, y: -11)
        case .error:
            Image(systemName: "exclamationmark")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Theme.warn)
                .frame(width: 13, height: 13)
                .background(.thinMaterial, in: Circle())
                .offset(x: -12, y: -12)
        case .cancelled:
            Circle()
                .fill(Theme.faint.opacity(0.2))
                .frame(width: 8, height: 8)
                .offset(x: -13, y: -12)
        case .hidden, .idle, .analyzing, .buildingRecommendation, .streaming, .success:
            EmptyView()
        }
    }

    private var bodyOffset: CGFloat {
        guard shouldAnimate else { return state == .cancelled ? 2 : 0 }
        switch state {
        case .buildingRecommendation:
            return loop ? -3 : 1
        case .streaming, .analyzing, .preparing:
            return loop ? -2 : 1
        default:
            return 0
        }
    }

    private var horizontalOffset: CGFloat {
        guard shouldAnimate else { return 0 }
        switch state {
        case .analyzing:
            return loop ? -0.8 : 0.8
        case .buildingRecommendation:
            return loop ? 0.8 : -0.8
        default:
            return 0
        }
    }

    private var rotationAngle: Double {
        guard shouldAnimate else { return 0 }
        switch state {
        case .buildingRecommendation:
            return loop ? -1.8 : 1.8
        case .analyzing:
            return loop ? 1.2 : -1.2
        default:
            return 0
        }
    }

    private var scale: CGFloat {
        if state == .success {
            return shouldAnimate && loop ? 1.03 : 1
        }
        if state == .preparing {
            return shouldAnimate && loop ? 1.015 : 1
        }
        return 1
    }

    private func startAnimationIfNeeded() {
        loop = false
        guard shouldAnimate else { return }
        withAnimation(.easeInOut(duration: state == .buildingRecommendation ? 0.7 : 0.8).repeatForever(autoreverses: true)) {
            loop = true
        }
    }
}

private struct CoachInlineFailureCard: View {
    let message: ChatMessage
    let language: CoachLanguage
    let onRetry: () -> Void
    let onDismiss: () -> Void
    let onCancel: () -> Void
    let onCheckStatus: () -> Void
    let onChooseDataAgain: () -> Void
    let onCheckConnection: () -> Void

    private var category: CoachErrorCategory {
        message.errorCategory ?? .retryableResponse
    }

    private var title: String {
        if message.assistantStatus == .retrying { return language.retryingInlineTitle }
        if message.assistantStatus == .reconciling { return language.mutationReconciliationTitle }
        if category == .missingAttachment { return language.missingAttachmentFailureTitle }
        if category == .responseTruncated { return language.responseTruncatedTitle }
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
                        .accessibilityLabel(language.cancelRetryAccessibilityLabel)
                } else if message.assistantStatus == .reconciling || category == .mutationUnknown {
                    Spacer(minLength: 0)
                    inlineButton(language.checkStatusLabel, role: .primary, action: onCheckStatus)
                        .accessibilityLabel(language.checkUpdateStatusAccessibilityLabel)
                } else if category == .missingAttachment {
                    inlineButton(language.dismissInlineErrorLabel, role: .secondary, action: onDismiss)
                    Spacer(minLength: 0)
                    inlineButton(language.chooseDataAgainLabel, role: .primary, action: onChooseDataAgain)
                } else if category == .authentication {
                    inlineButton(language.dismissInlineErrorLabel, role: .secondary, action: onDismiss)
                    Spacer(minLength: 0)
                    inlineButton(language.checkConnectionLabel, role: .primary, action: onCheckConnection)
                } else {
                    inlineButton(language.dismissInlineErrorLabel, role: .secondary, action: onDismiss)
                        .accessibilityLabel(language.dismissResponseErrorAccessibilityLabel)
                    Spacer(minLength: 0)
                    inlineButton(language.retryLabel, role: .primary, action: onRetry)
                        .accessibilityLabel(language.retryResponseAccessibilityLabel)
                }
            }
            .frame(minHeight: 44)

            if let detail = message.errorDetail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.faint)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(detail)
            }
        }
        .padding(12)
        .frame(maxWidth: 310, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.coachResponseInterruptedLabel)
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
