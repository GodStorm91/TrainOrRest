import CoreImage
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ChatView: View {
    private let bottomNavigation: AnyView?
    private let reviewRequest: CalendarReviewChatRequest?
    private let contextualWorkoutID: UUID?
    private let contextualCompletedActivityID: UUID?
    private let onOpenCalendar: (Date?) -> Void
    private let onReviewRequestConsumed: (CalendarReviewChatRequest) -> Void

    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ChatMessage.date) private var allMessages: [ChatMessage]
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var chatThreads: [ChatThread]
    @Query(sort: \PlannedWorkout.date) private var plannedWorkouts: [PlannedWorkout]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessDays: [DailyReadiness]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var completedActivities: [CompletedActivity]
    @EnvironmentObject private var chatStore: CoachChatStore
    @EnvironmentObject private var chatSession: CoachChatSessionState
    @EnvironmentObject private var replacementCoordinator: WorkoutReplacementCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var hasAPIKey = false
    @State private var evidence = EvidenceSelection()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageAttachment: CoachImageAttachment?
    @State private var selectedImage: UIImage?
    @State private var evidenceReview: EvidenceReviewPresentation?
    @State private var isChatListPresented = false
    @State private var isSavedPromptsPresented = false
    @State private var isHeaderCollapsed = false
    @State private var softwareKeyboardHeight: CGFloat = 0
    @State private var planTransaction: ChatPlanTransaction?
    @State private var lastConsumedReviewRequestID: UUID?
    @State private var submittingPromptSuggestionKeys = Set<String>()
    @State private var submittingInteractionID: String?
    @State private var pendingOtherResponse: PendingOtherCoachResponse?
    @FocusState private var composerFocused: Bool
    @AppStorage("coachEvidenceReviewed") private var coachEvidenceReviewed = false
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private let calendar = Calendar.current
    private let bottomAnchorID = "chat-feed-bottom-anchor"

    init(
        bottomNavigation: AnyView? = nil,
        reviewRequest: CalendarReviewChatRequest? = nil,
        contextualWorkoutID: UUID? = nil,
        contextualCompletedActivityID: UUID? = nil,
        onOpenCalendar: @escaping (Date?) -> Void = { _ in },
        onReviewRequestConsumed: @escaping (CalendarReviewChatRequest) -> Void = { _ in }
    ) {
        self.bottomNavigation = bottomNavigation
        self.reviewRequest = reviewRequest
        self.contextualWorkoutID = contextualWorkoutID
        self.contextualCompletedActivityID = contextualCompletedActivityID
        self.onOpenCalendar = onOpenCalendar
        self.onReviewRequestConsumed = onReviewRequestConsumed
    }

    private var language: CoachLanguage {
        CoachLanguage(rawValue: languageRaw) ?? .en
    }

    private var messages: [ChatMessage] {
        guard let activeThreadID = chatSession.activeThreadID else { return [] }
        return allMessages.filter { $0.threadID == activeThreadID && !isPlanAuditMessage($0) }
    }

    private var isSoftwareKeyboardVisible: Bool { softwareKeyboardHeight > 80 }
    private var isContextualSession: Bool { contextualWorkoutID != nil || contextualCompletedActivityID != nil }

    private var activeThread: ChatThread? {
        guard let activeThreadID = chatSession.activeThreadID else { return nil }
        return chatThreads.first { $0.uuid == activeThreadID }
    }

    private var contextualWorkout: PlannedWorkout? {
        guard let contextualWorkoutID else { return nil }
        return plannedWorkouts.first { $0.uuid == contextualWorkoutID }
    }

    private var contextualActivity: CompletedActivity? {
        guard let contextualCompletedActivityID else { return nil }
        return completedActivities.first { $0.hkUUID == contextualCompletedActivityID }
    }

    var body: some View {
        ZStack(alignment: .top) {
            chatBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if !hasAPIKey {
                    missingKeyView
                        .padding(.top, 72)
                } else if messages.isEmpty {
                    emptyState
                        .padding(.top, 74)
                } else {
                    messageFeed
                        .padding(.top, 70)
                }
                if hasAPIKey {
                    chatFooter
                }
            }

            topControlDeck
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            refreshKeyState()
            chatStore.resetError()
            migrateLegacyMessagesIfNeeded()
            removePersistedTransientErrorMessages()
            if isContextualSession {
                createOrResumeContextualThread()
            } else if reviewRequest == nil {
                createNewThreadForOpeningIfNeeded()
            }
            consumeReviewRequestIfNeeded()
        }
        .onAppear {
            if isContextualSession {
                NotificationCenter.default.post(name: .torSetBottomDockHidden, object: true)
            }
            refreshKeyState()
            chatStore.resetError()
            migrateLegacyMessagesIfNeeded()
            removePersistedTransientErrorMessages()
            if isContextualSession {
                createOrResumeContextualThread()
            } else if reviewRequest == nil {
                createNewThreadForOpeningIfNeeded()
            }
            consumeReviewRequestIfNeeded()
        }
        .onDisappear {
            if isContextualSession {
                NotificationCenter.default.post(name: .torSetBottomDockHidden, object: false)
            }
        }
        .onChange(of: allMessages.count) {
            attachUnthreadedMessagesToActiveThread()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            loadImageAttachment(from: item)
        }
        .onChange(of: reviewRequest?.id) { _, _ in
            consumeReviewRequestIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            updateKeyboardHeight(from: notification, forceHidden: true)
        }
        .sheet(item: $evidenceReview) { review in
            GroundingReviewSheet(
                snapshot: review.snapshot,
                requiresConfirmation: review.pendingSend != nil,
                onCancel: { evidenceReview = nil },
                onConfirm: {
                    coachEvidenceReviewed = true
                    let pending = review.pendingSend
                    evidenceReview = nil
                    if let pending {
                        performSend(pending)
                    }
                }
            )
        }
        .sheet(isPresented: $isChatListPresented) {
            ChatHistorySheet(threads: chatThreads, activeThreadID: chatSession.activeThreadID) { threadID in
                chatSession.activeThreadID = threadID
                isChatListPresented = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isSavedPromptsPresented) {
            SavedPromptsSheet(prompts: savedPrompts) { prompt in
                draft = prompt
                composerFocused = true
                isSavedPromptsPresented = false
            }
            .presentationDetents([.height(310), .medium])
        }
    }

    private var chatBackground: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                colors: [
                    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x07070C) : UIColor(hex: 0xFFFEFB) }),
                    Theme.bg,
                    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x10111A) : UIColor(hex: 0xF2F3F6) })
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.055), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            RadialGradient(
                colors: [Theme.good.opacity(0.045), .clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
        }
    }

    private var topControlDeck: some View {
        HStack(spacing: 10) {
            Button {
                if isContextualSession {
                    dismiss()
                } else {
                    isChatListPresented = true
                }
            } label: {
                Image(systemName: isContextualSession ? "chevron.left" : "line.3.horizontal")
                    .torTopControlIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isContextualSession ? "Quay lại Lịch" : "Mở menu")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    if !isHeaderCollapsed { CoachAvatar(size: 24).accessibilityHidden(true) }
                    Text("Coach")
                        .font(.torHeading(isHeaderCollapsed ? 16 : 18, .bold))
                        .foregroundStyle(Theme.text)
                }
                if !isHeaderCollapsed, let subtitle = headerSubtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if !isContextualSession {
                    Button { createNewThread() } label: {
                        Label("Cuộc trò chuyện mới", systemImage: "square.and.pencil")
                    }
                    Button { isChatListPresented = true } label: {
                        Label("Lịch sử trò chuyện", systemImage: "clock.arrow.circlepath")
                    }
                }
                NavigationLink { SettingsView() } label: {
                    Label("Cài đặt", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: isHeaderCollapsed ? "ellipsis" : "square.and.pencil")
                    .torTopControlIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isContextualSession ? "Tùy chọn Coach" : "Cuộc trò chuyện mới")
        }
        .frame(height: isHeaderCollapsed ? 44 : 52)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .torGlass(cornerRadius: isHeaderCollapsed ? 22 : 24, tint: .subtle)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHeaderCollapsed)
    }

    private var headerSubtitle: String? {
        if let workout = contextualWorkout {
            let verb = workout.status == .planned && !workout.isScheduleLocked && workout.kind != .race ? "Đang chỉnh buổi tập" : "Xem lại cùng Coach"
            return "\(verb) · \(workout.kind?.displayName ?? "Run") · \(workout.date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        if let activity = contextualActivity {
            let distance = Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: "")
            return "Xem lại cùng Coach · \(distance) · \(activity.date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        if let updated = latestGroundingTimeText {
            return "Dữ liệu cập nhật lúc \(updated)"
        }
        return nil
    }

    private var coachHeader: some View {
        HStack(spacing: 9) {
            CoachAvatar(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Coach")
                    .font(.torHeading(17, .bold))
                    .foregroundStyle(Theme.text)
                Text("Explains & proposes · never edits your plan.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Text(language.flag)
                .font(.system(size: 15))
                .accessibilityLabel(language.englishName)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isContextualSession {
                    contextualWorkoutCard
                        .padding(.top, 54)
                    contextualPromptRows
                } else {
                    readinessGlassCard
                        .padding(.top, 54)
                    suggestedPromptRows
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contextualWorkoutCard: some View {
        TorCard(padding: 16, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: contextualSymbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        TorEyebrow(contextualEyebrow).tracking(1.4)
                        Text(contextualTitle)
                            .font(.torHeading(20, .bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(contextualDateText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    ForEach(contextualMetricPairs.prefix(3), id: \.0) { pair in
                        ContextualWorkoutMetricChip(label: pair.0, value: pair.1)
                    }
                }

                if let workout = contextualWorkout {
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        Label("View workout details", systemImage: "doc.text.magnifyingglass")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open workout details")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(contextualAccessibilityLabel)
    }

    private var contextualPromptRows: some View {
        VStack(spacing: 9) {
            ForEach(visibleContextualPromptSuggestions.prefix(2)) { suggestion in
                ChatPromptButton(suggestion.prompt, systemImage: suggestion.prompt.contains("Move") || suggestion.prompt.contains("lịch") ? "calendar.badge.clock" : "sparkles") {
                    submitPromptSuggestion(suggestion)
                }
            }
        }
    }

    private var readinessGlassCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(todayReadinessTint.opacity(0.16))
                    Circle().strokeBorder(todayReadinessTint.opacity(0.28), lineWidth: 1)
                    Circle().fill(todayReadinessTint).frame(width: 9, height: 9)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text(todayReadinessTitle)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(todayReadinessSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Theme.border)

            HStack(spacing: 10) {
                Image(systemName: todayWorkout?.kind?.symbolName ?? "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.good)
                    .frame(width: 24, height: 24)
                    .background(Theme.good.opacity(0.12), in: Circle())
                Text(todayPlannedWorkoutText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            Button { draft = "Xem kế hoạch hôm nay" } label: {
                HStack(spacing: 8) {
                    Text("Xem kế hoạch hôm nay")
                        .font(.callout.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .torGlass(cornerRadius: 26, tint: .graphite)
    }

    private var suggestedPromptRows: some View {
        VStack(spacing: 9) {
            ForEach(visibleOpeningPromptSuggestions.prefix(3)) { suggestion in
                ChatPromptButton(suggestion.prompt, systemImage: openingPromptIcon(for: suggestion.id)) {
                    submitPromptSuggestion(suggestion)
                }
            }
        }
    }

    private var messageFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ChatScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("chatFeed")).minY
                    )
                }
                .frame(height: 0)

                LazyVStack(spacing: 14) {
                    if isContextualSession {
                        compactContextChip
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.turnID) { index, message in
                        ChatBubble(
                            message: message,
                            hidesSources: isSoftwareKeyboardVisible,
                            showsAvatar: shouldShowAssistantAvatar(at: index),
                            showsSource: shouldShowAssistantSource(at: index),
                            isGroupedWithPrevious: isGroupedWithPreviousMessage(at: index),
                            language: language,
                            onRetry: { failedTurn in
                                Task {
                                    await chatStore.retryFailedResponse(
                                        failedTurn.turnID,
                                        model: model,
                                        in: modelContext
                                    )
                                }
                            },
                            onDismissFailure: { failedTurn in
                                chatStore.dismissFailedResponse(failedTurn.turnID, in: modelContext)
                            },
                            onCancelRetry: { failedTurn in
                                chatStore.cancelRetry(failedTurn.turnID, in: modelContext)
                            },
                            actionableInteractionID: newestPendingInteractionID,
                            isSubmittingInteraction: submittingInteractionID == message.interaction?.id,
                            onSelectInteractionOption: selectInteractionOption,
                            onSelectInteractionOther: selectInteractionOther
                        )
                        .id(message.turnID)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .coordinateSpace(name: "chatFeed")
            .onPreferenceChange(ChatScrollOffsetPreferenceKey.self) { offset in
                let collapsed = offset < -26
                if collapsed != isHeaderCollapsed {
                    if reduceMotion {
                        isHeaderCollapsed = collapsed
                    } else {
                        withAnimation(.easeOut(duration: 0.16)) { isHeaderCollapsed = collapsed }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: chatStore.isSending) {
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: chatSession.activeThreadID) {
                scrollToBottom(proxy, animated: false)
            }
        }
    }


    private var latestGroundingTimeText: String? {
        messages.reversed().compactMap(groundingTimeText).first
    }

    private func groundingTimeText(for message: ChatMessage) -> String? {
        guard let footnote = message.groundingFootnote else { return nil }
        let raw = footnote.components(separatedBy: " · ").first?.replacingOccurrences(of: "Based on ", with: "") ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func isGroupedWithPreviousMessage(at index: Int) -> Bool {
        guard index > 0, messages[index].role == .assistant else { return false }
        return messages[index - 1].role == .assistant
    }

    private func shouldShowAssistantAvatar(at index: Int) -> Bool {
        guard messages[index].role == .assistant else { return true }
        return !isGroupedWithPreviousMessage(at: index)
    }

    private func shouldShowAssistantSource(at index: Int) -> Bool {
        guard messages[index].role == .assistant else { return false }
        let isLastInAssistantGroup = index == messages.indices.last || messages[index + 1].role != .assistant
        return isLastInAssistantGroup && messages[index].groundingFootnote != nil
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {        guard !messages.isEmpty else { return }
        let action = { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { action() }
            } else {
                action()
            }
        }
    }

    private var missingKeyView: some View {
        ContentUnavailableView {
            Label("API Key Needed", systemImage: "key")
        } description: {
            Text("Add a \(CoachModelProvider.displayName(for: model)) API key before chatting.")
        } actions: {
            NavigationLink("Add API key") {
                CoachProviderSettingsView()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var chatFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let transaction = planTransaction {
                PlanTransactionCard(
                    transaction: transaction,
                    onViewCalendar: {
                        if isContextualSession {
                            dismiss()
                        } else {
                            onOpenCalendar(planTransaction?.calendarDate)
                        }
                    },
                    onUndo: { planTransaction = nil },
                    onRetry: retryPlanTransaction,
                    onDismiss: { planTransaction = nil }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let pending = replacementCoordinator.pending {
                PlanUpdateCard(
                    pending: pending,
                    language: language,
                    isApplying: replacementCoordinator.isConfirming,
                    onApply: { applyReplacement(pending) },
                    onKeep: { replacementCoordinator.cancel() },
                    onAskWhy: {
                        replacementCoordinator.cancel()
                        draft = language.whySwapPrompt
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let pending = replacementCoordinator.pendingProposal {
                PlanProposalCard(
                    pending: pending,
                    language: language,
                    isApplying: replacementCoordinator.isConfirming,
                    onApply: { applyProposal(pending) },
                    onKeep: { replacementCoordinator.cancel() }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if shouldShowContextualSuggestions {
                CoachAskNextStrip(
                    prompts: Array(visibleContextualPromptSuggestions.prefix(2).map(\.prompt)),
                    label: contextualSuggestionLabel
                ) { prompt in
                    if let suggestion = visibleContextualPromptSuggestions.first(where: { $0.prompt == prompt }) {
                        submitPromptSuggestion(suggestion)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if shouldShowDraftRelativeDateSuggestions {
                CoachAskNextStrip(
                    prompts: draftRelativeDateSuggestions,
                    label: "MATCHED WORKOUT"
                ) { prompt in
                    draft = prompt
                    composerFocused = true
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if shouldShowSuggestions {
                CoachAskNextStrip(prompts: Array(visiblePromptSuggestions.prefix(2).map(\.prompt)), label: language.askNextLabel) { prompt in
                    if let suggestion = visiblePromptSuggestions.first(where: { $0.prompt == prompt }) {
                        submitPromptSuggestion(suggestion)
                    }
                }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            attachmentChips
            composer
            if let bottomNavigation, !isSoftwareKeyboardVisible {
                bottomNavigation
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, isSoftwareKeyboardVisible ? 6 : (bottomNavigation.map { _ in 4 } ?? 8))
        .background(.clear)
        .animation(.easeOut(duration: 0.2), value: replacementCoordinator.pending)
        .animation(.easeOut(duration: 0.2), value: replacementCoordinator.pendingProposal)
        .animation(.easeOut(duration: 0.2), value: isSoftwareKeyboardVisible)
    }

    private var shouldShowSuggestions: Bool {
        !hasPendingInteraction && !isContextualSession && !isSoftwareKeyboardVisible && !messages.isEmpty && !chatStore.isSending && !visiblePromptSuggestions.isEmpty
    }

    private var shouldShowContextualSuggestions: Bool {
        isContextualSession
            && !hasPendingInteraction
            && !isSoftwareKeyboardVisible
            && !chatStore.isSending
            && !replacementCoordinator.hasPendingDecision
            && !replacementCoordinator.isConfirming
            && messages.count <= 2
            && !visibleContextualPromptSuggestions.isEmpty
    }

    private var shouldShowDraftRelativeDateSuggestions: Bool {
        !draftRelativeDateSuggestions.isEmpty
            && !chatStore.isSending
            && !replacementCoordinator.hasPendingDecision
            && !replacementCoordinator.isConfirming
    }

    private var draftRelativeDateSuggestions: [String] {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3, clean.containsTomorrowReference else { return [] }

        guard let workout = tomorrowWorkout else {
            return ["Ngày mai chưa có bài trong lịch. Tạo một buổi tập mới cho ngày mai?"]
        }

        let workoutText = "\(workout.kind?.displayName ?? "Workout") · \(kmText(workout.distanceKm))"
        if let requestedKm = clean.requestedDistanceKmText {
            return ["Đổi buổi training ngày mai (\(workoutText)) thành \(requestedKm), giữ cùng loại bài nếu an toàn."]
        }

        if clean.requestsTimeSuggestion {
            return ["Tìm giờ tốt cho buổi training ngày mai (\(workoutText))."]
        }

        if clean.requestsScheduleMove {
            return ["Cập nhật lịch cho buổi training ngày mai (\(workoutText))."]
        }

        return ["Ngày mai có \(workoutText). Anh muốn cập nhật buổi này thế nào?"]
    }

    private var newestPendingInteractionID: String? {
        messages.reversed().compactMap { message -> String? in
            guard message.role == .assistant,
                  message.assistantStatus == .completed,
                  message.interaction?.status == .pending else { return nil }
            return message.interaction?.id
        }.first
    }

    private var hasPendingInteraction: Bool {
        newestPendingInteractionID != nil
    }

    private var visiblePromptSuggestions: [CoachPromptSuggestion] {
        guard let conversationId = chatSession.activeThreadID else { return [] }
        let candidates = suggestionPrompts.enumerated().map { index, prompt in
            CoachPromptSuggestion(
                id: "general-\(index)-\(prompt.stableSuggestionID)",
                conversationId: conversationId,
                title: prompt,
                prompt: prompt,
                status: .available
            )
        }
        return chatStore.promptSuggestions(from: candidates, in: modelContext)
            .filter { !submittingPromptSuggestionKeys.contains($0.scopeKey) }
    }

    private var visibleContextualPromptSuggestions: [CoachPromptSuggestion] {
        guard let conversationId = chatSession.activeThreadID else { return [] }
        let workoutId = contextualWorkoutID ?? contextualCompletedActivityID
        let candidates = contextualSuggestionPrompts.enumerated().map { index, prompt in
            CoachPromptSuggestion(
                id: "context-\(index)-\(prompt.stableSuggestionID)",
                workoutId: workoutId,
                conversationId: conversationId,
                title: prompt,
                prompt: prompt,
                status: .available
            )
        }
        return chatStore.promptSuggestions(from: candidates, in: modelContext)
            .filter { !submittingPromptSuggestionKeys.contains($0.scopeKey) }
    }

    private var visibleOpeningPromptSuggestions: [CoachPromptSuggestion] {
        guard let conversationId = chatSession.activeThreadID else { return [] }
        let prompts = [
            ("latest-run", "Phân tích buổi tập gần nhất"),
            ("weekly-load", "Tải tập tuần này của tôi thế nào?"),
            ("today-workout", "Hôm nay tôi nên tập gì?")
        ]
        let candidates = prompts.map { id, prompt in
            CoachPromptSuggestion(
                id: "opening-\(id)",
                conversationId: conversationId,
                title: prompt,
                prompt: prompt,
                status: .available
            )
        }
        return chatStore.promptSuggestions(from: candidates, in: modelContext)
            .filter { !submittingPromptSuggestionKeys.contains($0.scopeKey) }
    }

    private func openingPromptIcon(for id: String) -> String {
        if id.contains("latest-run") { return "waveform.path.ecg" }
        if id.contains("weekly-load") { return "chart.line.uptrend.xyaxis" }
        return "sun.max"
    }

    @ViewBuilder
    private var attachmentChips: some View {
        if isContextualSession || evidence.readinessSnapshot || evidence.workout != nil || selectedImageAttachment != nil {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                if isContextualSession {
                    fixedContextChip
                }
                if evidence.readinessSnapshot {
                    removableChip("Dữ liệu sức khỏe", symbol: "heart.fill") { evidence.readinessSnapshot = false }
                }
                if evidence.workout != nil {
                    removableChip("Buổi tập gần nhất", symbol: "figure.run") { evidence.workout = nil }
                }
                if selectedImageAttachment != nil {
                    removableChip("Ảnh", symbol: "photo") { clearImageAttachment() }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func removableChip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xóa \(title)")
        }
        .foregroundStyle(Theme.text)
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background(Theme.chip, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Menu {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Đính kèm hình ảnh", systemImage: "photo")
                }
                Button { evidence.readinessSnapshot = true } label: {
                    Label("Dữ liệu sức khỏe", systemImage: "heart")
                }
                Button { attachLatestWorkout() } label: {
                    Label("Buổi tập", systemImage: "figure.run")
                }
                Button { isSavedPromptsPresented = true } label: {
                    Label("Câu hỏi đã lưu", systemImage: "bookmark")
                }
                .accessibilityLabel("Mở câu hỏi đã lưu")
                if selectedImageAttachment != nil {
                    Button(role: .destructive) { clearImageAttachment() } label: {
                        Label("Xóa ảnh", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thêm nội dung")

            TextField(composerPlaceholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .lineLimit(1...5)
                .padding(.vertical, 12)
                .focused($composerFocused)
                .disabled((replacementCoordinator.hasPendingDecision || replacementCoordinator.isConfirming) && pendingOtherResponse == nil)

            if isSoftwareKeyboardVisible {
                Button {
                    composerFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ẩn bàn phím")
            }

            Button {
                send()
            } label: {
                Group {
                    if chatStore.isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.accentSoft, radius: 8, y: 3)
                .opacity(isSendDisabled ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Gửi tin nhắn")
            .disabled(isSendDisabled)
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .torGlass(cornerRadius: 26, tint: .graphite)
    }


    private var savedPrompts: [String] {
        [
            "Hôm nay tôi nên tập gì?",
            "Tải tập tuần này của tôi thế nào?",
            "Làm sao để phục hồi nhanh hơn?",
            "Buổi sau có nên tăng cường độ không?"
        ]
    }

    private func attachLatestWorkout() {
        if let activity = completedActivities.first {
            evidence.workout = .completed(activity.hkUUID)
        } else if let workout = plannedWorkouts.first(where: { $0.date >= calendar.startOfDay(for: .now) }) {
            evidence.workout = .planned(workout.uuid)
        } else {
            draft = "Chọn buổi tập gần nhất để Coach phân tích"
            composerFocused = true
        }
    }

    private var isSendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || chatStore.isSending
            || (replacementCoordinator.hasPendingDecision && pendingOtherResponse == nil)
            || replacementCoordinator.isConfirming
    }

    // MARK: - Ask Next suggestions

    private var suggestionPrompts: [String] {
        CoachSuggestions.prompts(for: suggestionContext, language: language)
    }

    private var suggestionContext: CoachSuggestions.Context {
        let recent = completedActivities.first
        let recentIsRecent = recent.map { isWithinRecentWindow($0.date) } ?? false
        let recentIsHard = recent.map(isHardEffort) ?? false
        return CoachSuggestions.Context(
            hasMessages: !messages.isEmpty,
            lastMessageIsAssistant: messages.last?.role == .assistant,
            hasRecentRun: recentIsRecent,
            recentRunWasHard: recentIsHard,
            todayWorkoutKind: plannedWorkouts.first { calendar.isDateInToday($0.date) }?.kind
        )
    }

    private var todayReadiness: DailyReadiness? {
        readinessDays.first { calendar.isDateInToday($0.date) }
    }

    private var todayWorkout: PlannedWorkout? {
        plannedWorkouts
            .filter { calendar.isDateInToday($0.date) && $0.status == .planned }
            .sorted { $0.date < $1.date }
            .first
    }

    private var tomorrowWorkout: PlannedWorkout? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) else {
            return nil
        }
        return plannedWorkouts
            .filter { calendar.isDate($0.date, inSameDayAs: tomorrow) && $0.status == .planned }
            .sorted { $0.date < $1.date }
            .first
    }

    private var todayReadinessTint: Color {
        todayReadiness?.verdict.torColor ?? Theme.dim
    }

    private var todayReadinessTitle: String {
        guard let verdict = todayReadiness?.verdict else { return "Hôm nay: Đang cập nhật" }
        switch verdict {
        case .train: return "Hôm nay: Sẵn sàng tập luyện"
        case .goEasy: return "Hôm nay: Nên tập nhẹ"
        case .rest: return "Hôm nay: Ưu tiên phục hồi"
        case .insufficientData: return "Hôm nay: Đang xây baseline"
        }
    }

    private var todayReadinessSubtitle: String {
        guard let readiness = todayReadiness else { return "Chưa có verdict mới nhất từ dữ liệu sức khỏe." }
        if readiness.reasons.isEmpty {
            return readiness.verdict == .train ? "Phục hồi tốt · Chưa có dấu hiệu quá tải" : readiness.verdict.torSubtitle
        }
        return Array(readiness.reasons.prefix(2)).joined(separator: " · ")
    }

    private var todayPlannedWorkoutText: String {
        guard let workout = todayWorkout else { return "Không có bài dự kiến hôm nay" }
        var parts: [String] = []
        parts.append(workout.kind?.displayName ?? "Run")
        parts.append(kmText(workout.distanceKm))
        if let band = workout.paceBand {
            parts.append(Formatters.paceBand(band).replacingOccurrences(of: " /km", with: "/km"))
        }
        return "Bài dự kiến: " + parts.joined(separator: " · ")
    }

    private func kmText(_ km: Double) -> String {
        abs(km.rounded() - km) < 0.05 ? "\(Int(km.rounded())) km" : String(format: "%.1f km", km)
    }

    /// A run counts as "recent" when it finished within the last two days.
    private func isWithinRecentWindow(_ date: Date) -> Bool {
        guard date <= .now else { return false }
        let days = calendar.dateComponents([.day], from: date, to: .now).day ?? .max
        return days <= 2
    }

    private func isHardEffort(_ activity: CompletedActivity) -> Bool {
        if let hr = activity.avgHeartRate, hr >= 160 { return true }
        if let pace = activity.avgPaceSecondsPerKm, pace < 300 { return true }
        return false
    }

    private func send() {
        let text = draft
        let attachments = currentAttachments
        let pending = PendingCoachSend(
            text: text,
            attachments: attachments,
            evidence: evidence,
            interactionId: pendingOtherResponse?.interactionID,
            selectedOptionId: nil,
            isCustomInteractionResponse: pendingOtherResponse != nil,
            interactionMessageID: pendingOtherResponse?.messageID
        )
        guard coachEvidenceReviewed else {
            presentEvidenceReview(confirming: pending)
            return
        }
        performSend(pending)
    }

    private func performSend(_ pending: PendingCoachSend) {
        let previousInteraction = pending.interactionMessageID.flatMap { id in
            messages.first(where: { $0.turnID == id })?.interaction
        }
        if let messageID = pending.interactionMessageID {
            _ = chatStore.resolveInteraction(
                messageID: messageID,
                selectedOptionId: pending.selectedOptionId,
                resolvedWithOther: pending.isCustomInteractionResponse,
                in: modelContext
            )
        }
        let reviewedSnapshot = pending.reviewedSnapshot
        let threadID = chatSession.activeThreadID ?? createNewThread()
        draft = ""
        pendingOtherResponse = nil
        evidence = isContextualSession ? contextualEvidenceSelection : EvidenceSelection()
        clearImageAttachment()
        composerFocused = true
        Task {
            let didSend = await chatStore.send(
                text: pending.text,
                model: model,
                attachments: pending.attachments,
                evidence: pending.evidence,
                groundingSnapshot: reviewedSnapshot,
                threadID: threadID,
                interactionId: pending.interactionId,
                selectedOptionId: pending.selectedOptionId,
                isCustomInteractionResponse: pending.isCustomInteractionResponse,
                in: modelContext
            )
            await MainActor.run {
                if !didSend, let previousInteraction, let messageID = pending.interactionMessageID {
                    chatStore.restoreInteraction(messageID: messageID, interaction: previousInteraction, in: modelContext)
                }
                composerFocused = true
            }
        }
    }

    private func submitPromptSuggestion(_ suggestion: CoachPromptSuggestion) {
        guard !submittingPromptSuggestionKeys.contains(suggestion.scopeKey), !chatStore.isSending else { return }
        submittingPromptSuggestionKeys.insert(suggestion.scopeKey)
        chatStore.setPromptSuggestionStatus(.consumed, for: suggestion, in: modelContext)
        let attachments = currentAttachments
        let pending = PendingCoachSend(text: suggestion.prompt, attachments: attachments, evidence: evidence)
        Task {
            let didSend = await sendAlreadyReviewed(pending)
            await MainActor.run {
                submittingPromptSuggestionKeys.remove(suggestion.scopeKey)
                if !didSend {
                    chatStore.setPromptSuggestionStatus(.available, for: suggestion, in: modelContext)
                }
            }
        }
    }

    private func sendAlreadyReviewed(_ pending: PendingCoachSend) async -> Bool {
        let threadID = chatSession.activeThreadID ?? createNewThread()
        await MainActor.run {
            draft = ""
            pendingOtherResponse = nil
            evidence = isContextualSession ? contextualEvidenceSelection : EvidenceSelection()
            clearImageAttachment()
            composerFocused = true
        }
        return await chatStore.send(
            text: pending.text,
            model: model,
            attachments: pending.attachments,
            evidence: pending.evidence,
            groundingSnapshot: pending.reviewedSnapshot,
            threadID: threadID,
            interactionId: pending.interactionId,
            selectedOptionId: pending.selectedOptionId,
            isCustomInteractionResponse: pending.isCustomInteractionResponse,
            in: modelContext
        )
    }

    private func selectInteractionOption(_ message: ChatMessage, option: CoachChoiceOption) {
        guard submittingInteractionID == nil,
              let interaction = message.interaction,
              interaction.status == .pending,
              interaction.id == newestPendingInteractionID else { return }
        submittingInteractionID = interaction.id
        let previousInteraction = interaction
        _ = chatStore.resolveInteraction(
            messageID: message.turnID,
            selectedOptionId: option.id,
            in: modelContext
        )
        let pending = PendingCoachSend(
            text: option.value,
            attachments: currentAttachments,
            evidence: evidence,
            interactionId: interaction.id,
            selectedOptionId: option.id,
            interactionMessageID: message.turnID
        )
        Task {
            let didSend = await sendAlreadyReviewed(pending)
            await MainActor.run {
                submittingInteractionID = nil
                if !didSend {
                    chatStore.restoreInteraction(messageID: message.turnID, interaction: previousInteraction, in: modelContext)
                }
            }
        }
    }

    private func selectInteractionOther(_ message: ChatMessage, interaction: CoachResponseInteraction) {
        guard interaction.status == .pending, interaction.id == newestPendingInteractionID else { return }
        pendingOtherResponse = PendingOtherCoachResponse(
            messageID: message.turnID,
            interactionID: interaction.id,
            placeholder: interaction.otherPlaceholder ?? language.choiceOtherPlaceholder
        )
        composerFocused = true
    }

    private func applyReplacement(_ pending: PendingWorkoutReplacement) {
        planTransaction = .applying(title: "Đang cập nhật kế hoạch…")
        replacementCoordinator.confirm(pending.id)
        if let error = replacementCoordinator.lastError {
            planTransaction = .failure(userMessage: userFacingPlanError(error), technicalDetails: error, retry: .replacement(pending))
        } else if replacementCoordinator.pending != nil {
            planTransaction = nil
        } else {
            planTransaction = .success(summary: pending.successMessage, date: pending.date, undo: .safe)
        }
    }

    private func applyProposal(_ pending: PendingPlanProposal) {
        planTransaction = .applying(title: "Đang cập nhật kế hoạch…")
        replacementCoordinator.confirmProposal(pending.id)
        if let error = replacementCoordinator.lastError {
            planTransaction = .failure(userMessage: userFacingPlanError(error), technicalDetails: error, retry: .proposal(pending))
        } else if replacementCoordinator.pendingProposal != nil {
            planTransaction = nil
        } else {
            planTransaction = .success(summary: pending.summary, date: nil, undo: .unsafe)
        }
    }

    private func retryPlanTransaction() {
        guard case .failure(_, _, let retry) = planTransaction else { return }
        switch retry {
        case .replacement(let pending):
            planTransaction = nil
            replacementCoordinator.stage(pending)
        case .proposal(let pending):
            planTransaction = nil
            replacementCoordinator.stage(pending.proposal, summary: pending.summary, threadID: pending.threadID)
        }
    }

    private func userFacingPlanError(_ error: String) -> String {
        let lower = error.lowercased()
        if lower.contains("missing") || lower.contains("couldn't be read") || lower.contains("duration") || lower.contains("pace") {
            return "Kế hoạch còn thiếu thời lượng hoặc pace mục tiêu. Anh có thể để Coach tự đề xuất hoặc nhập thủ công."
        }
        if lower.contains("load") || lower.contains("volume") || lower.contains("ramp") || lower.contains("safe") {
            return "Buổi tập mới có thể khiến tải tập tuần này tăng quá nhanh."
        }
        return "Kế hoạch hiện tại chưa bị thay đổi."
    }

    private func presentEvidenceReview(confirming pending: PendingCoachSend?) {
        let selectedEvidence = pending?.evidence ?? evidence
        do {
            let snapshot = try CoachGrounding.snapshot(
                evidence: selectedEvidence,
                in: modelContext,
                today: Date(),
                calendar: calendar
            )
            let pendingWithSnapshot = pending.map {
                PendingCoachSend(
                    text: $0.text,
                    attachments: $0.attachments,
                    evidence: $0.evidence,
                    reviewedSnapshot: snapshot,
                    interactionId: $0.interactionId,
                    selectedOptionId: $0.selectedOptionId,
                    isCustomInteractionResponse: $0.isCustomInteractionResponse,
                    interactionMessageID: $0.interactionMessageID
                )
            }
            evidenceReview = EvidenceReviewPresentation(snapshot: snapshot, pendingSend: pendingWithSnapshot)
        } catch {
            chatStore.presentError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func createOrResumeContextualThread() {
        guard let snapshot = currentWorkoutCoachContext else {
            chatStore.presentError("This workout is no longer available.")
            return
        }

        let threadID: UUID
        if let existing = existingContextualThread(for: snapshot) {
            existing.archivedAt = nil
            existing.updatedAt = .now
            existing.contextualSnapshotJSON = WorkoutCoachContext.encode(snapshot)
            threadID = existing.uuid
        } else {
            let thread = ChatThread(
                title: contextualThreadTitle(for: snapshot),
                mode: snapshot.workoutStatus == .completed ? .workoutReview : .workoutEdit,
                linkedWorkoutUUID: snapshot.workoutId,
                linkedPlanUUID: snapshot.trainingPlanId,
                contextualSnapshotJSON: WorkoutCoachContext.encode(snapshot)
            )
            if let completedActivityId = snapshot.completedActivityId {
                thread.reviewActivityUUID = completedActivityId
            }
            modelContext.insert(thread)
            threadID = thread.uuid
        }
        chatSession.activeThreadID = threadID
        evidence = contextualEvidenceSelection
        try? modelContext.save()
    }

    private func existingContextualThread(for snapshot: WorkoutCoachContext) -> ChatThread? {
        if let workoutId = snapshot.workoutId {
            return chatThreads
                .filter { $0.linkedWorkoutUUID == workoutId && $0.mode == .workoutEdit && !$0.isStale(comparedTo: snapshot) }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
        }
        if let completedActivityId = snapshot.completedActivityId {
            return chatThreads
                .filter { $0.reviewActivityUUID == completedActivityId && $0.mode == .workoutReview }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
        }
        return nil
    }

    private func contextualThreadTitle(for snapshot: WorkoutCoachContext) -> String {
        let date = snapshot.calendarDate.formatted(.dateTime.month(.abbreviated).day())
        let prefix = snapshot.workoutStatus == .completed ? "Review" : "Edit"
        return "\(prefix) \(snapshot.workoutTitle) · \(date)"
    }

    private func consumeReviewRequestIfNeeded() {
        guard let request = reviewRequest, lastConsumedReviewRequestID != request.id else { return }
        lastConsumedReviewRequestID = request.id
        guard let activityUUID = request.activityUUID else {
            let threadID = createNewThread(title: "Calendar schedule review")
            draft = request.prompt
            evidence = EvidenceSelection(readinessSnapshot: true, weekPlan: true, workout: nil, hasPhoto: false)
            chatSession.activeThreadID = threadID
            composerFocused = true
            onReviewRequestConsumed(request)
            return
        }
        guard let activity = completedActivities.first(where: { $0.hkUUID == activityUUID }) else {
            chatStore.presentError("Không tìm thấy buổi chạy để review. Thử đồng bộ lại Health rồi mở lại Calendar.")
            onReviewRequestConsumed(request)
            return
        }

        let threadID: UUID
        if let existingThread = existingReviewThread(for: activity) {
            existingThread.reviewActivityUUID = activity.hkUUID
            existingThread.archivedAt = nil
            existingThread.updatedAt = .now
            try? modelContext.save()
            threadID = existingThread.uuid
            draft = messages(in: existingThread.uuid).isEmpty ? request.prompt : ""
        } else {
            threadID = createNewThread(title: reviewThreadTitle(for: activity), reviewActivityUUID: activity.hkUUID)
            draft = request.prompt
        }
        evidence = EvidenceSelection(readinessSnapshot: true, weekPlan: true, workout: .completed(activity.hkUUID), hasPhoto: false)
        chatSession.activeThreadID = threadID
        composerFocused = true
        onReviewRequestConsumed(request)
    }

    private func reviewThreadTitle(for activity: CompletedActivity) -> String {
        let distance = Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: "")
        let date = activity.date.formatted(.dateTime.month(.abbreviated).day())
        return "Review \(distance) run · \(date)"
    }

    private func existingReviewThread(for activity: CompletedActivity) -> ChatThread? {
        if let exact = chatThreads.first(where: { $0.reviewActivityUUID == activity.hkUUID }) {
            return exact
        }
        let title = reviewThreadTitle(for: activity)
        return chatThreads
            .filter { $0.reviewActivityUUID == nil && $0.title == title }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private func messages(in threadID: UUID) -> [ChatMessage] {
        allMessages.filter { $0.threadID == threadID }.sorted { $0.date < $1.date }
    }

    @discardableResult
    private func createNewThread(title: String = "New chat", reviewActivityUUID: UUID? = nil) -> UUID {
        let thread = ChatThread(title: title, reviewActivityUUID: reviewActivityUUID)
        modelContext.insert(thread)
        chatSession.activeThreadID = thread.uuid
        draft = ""
        evidence.workout = nil
        clearImageAttachment()
        try? modelContext.save()
        return thread.uuid
    }

    private func createNewThreadForOpeningIfNeeded() {
        if let activeThreadID = chatSession.activeThreadID {
            if chatThreads.contains(where: { $0.uuid == activeThreadID }) {
                return
            }
            chatSession.activeThreadID = nil
        }
        createNewThread()
    }

    private func migrateLegacyMessagesIfNeeded() {
        let legacyMessages = allMessages.filter { $0.threadID == nil }
        guard !legacyMessages.isEmpty else { return }
        let thread = ChatThread(
            title: "Previous chat",
            createdAt: legacyMessages.first?.date ?? .now,
            updatedAt: legacyMessages.last?.date ?? .now
        )
        modelContext.insert(thread)
        for message in legacyMessages {
            message.threadID = thread.uuid
        }
        try? modelContext.save()
    }

    private func attachUnthreadedMessagesToActiveThread() {
        guard let activeThreadID = chatSession.activeThreadID else { return }
        let unthreaded = allMessages.filter { $0.threadID == nil }
        guard !unthreaded.isEmpty else { return }
        for message in unthreaded {
            message.threadID = activeThreadID
        }
        if let thread = activeThread {
            thread.updatedAt = unthreaded.map(\.date).max() ?? .now
        }
        try? modelContext.save()
    }

    private func removePersistedTransientErrorMessages() {
        let transientMessages = allMessages.filter { message in
            message.role == .assistant && (
                message.text == ClaudeClientError.connectionLost.errorDescription ||
                message.text == ClaudeClientError.offline.errorDescription ||
                message.text == ClaudeClientError.rateLimited.errorDescription ||
                message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        guard !transientMessages.isEmpty else { return }
        transientMessages.forEach(modelContext.delete)
        try? modelContext.save()
    }

    private func refreshKeyState() {
        hasAPIKey = !((try? KeychainStore.load(account: CoachModelProvider.apiKeyAccount(for: model))) ?? "").isEmpty
    }

    private var currentWorkoutCoachContext: WorkoutCoachContext? {
        if let workout = contextualWorkout {
            let nearby = plannedWorkouts
                .filter { other in
                    other.uuid != workout.uuid
                        && abs(calendar.dateComponents([.day], from: workout.date, to: other.date).day ?? 99) <= 3
                }
                .map(\.uuid)
            return WorkoutCoachContext(
                workoutId: workout.uuid,
                trainingPlanId: nil,
                calendarDate: workout.date,
                workoutStatus: contextualStatus(for: workout),
                workoutType: workout.kindRaw,
                workoutTitle: workout.kind?.displayName ?? "Run",
                plannedDistanceKm: workout.distanceKm,
                plannedDurationSeconds: workout.expectedDurationSeconds,
                plannedPaceFastSecondsPerKm: workout.paceFastSecondsPerKm,
                plannedPaceSlowSecondsPerKm: workout.paceSlowSecondsPerKm,
                plannedIntensity: workout.kind?.isQuality == true ? "key" : "easy",
                workoutStructureSummary: workout.details,
                isKeyWorkout: workout.kind?.isQuality == true,
                phaseId: workout.phaseRaw,
                phaseName: TrainingPhase(rawValue: workout.phaseRaw)?.displayName ?? workout.phaseRaw,
                planWeek: workout.weekIndex,
                nearbyWorkoutIds: nearby,
                sourceScreen: "trainingCalendar"
            )
        }
        if let activity = contextualActivity {
            return WorkoutCoachContext(
                workoutId: nil,
                completedActivityId: activity.hkUUID,
                trainingPlanId: nil,
                calendarDate: activity.date,
                workoutStatus: .completed,
                workoutType: "completedRun",
                workoutTitle: "Completed run",
                plannedDistanceKm: nil,
                actualDistanceMeters: activity.distanceMeters,
                plannedDurationSeconds: nil,
                actualDurationSeconds: activity.durationSeconds,
                plannedPaceFastSecondsPerKm: nil,
                plannedPaceSlowSecondsPerKm: nil,
                plannedIntensity: nil,
                workoutStructureSummary: activity.reviewNote,
                isKeyWorkout: false,
                phaseId: nil,
                phaseName: nil,
                planWeek: nil,
                nearbyWorkoutIds: [],
                sourceScreen: "trainingCalendar"
            )
        }
        return nil
    }

    private func contextualStatus(for workout: PlannedWorkout) -> WorkoutCoachContext.Status {
        switch workout.status {
        case .planned:
            return workout.isScheduleLocked || workout.kind == .race ? .locked : .planned
        case .done:
            return .completed
        case .skipped:
            return .unavailable
        }
    }

    private var contextualEvidenceSelection: EvidenceSelection {
        if let contextualWorkoutID {
            return EvidenceSelection(readinessSnapshot: true, weekPlan: true, workout: .planned(contextualWorkoutID), hasPhoto: selectedImageAttachment != nil)
        }
        if let contextualCompletedActivityID {
            return EvidenceSelection(readinessSnapshot: true, weekPlan: true, workout: .completed(contextualCompletedActivityID), hasPhoto: selectedImageAttachment != nil)
        }
        return EvidenceSelection()
    }

    private var composerPlaceholder: String {
        if let pendingOtherResponse {
            return pendingOtherResponse.placeholder
        }
        if isContextualSession {
            return isSoftwareKeyboardVisible ? "Nội dung đang nhập…" : "Ask Coach to change this workout…"
        }
        return isSoftwareKeyboardVisible ? "Nội dung đang nhập…" : "Hỏi Coach bất cứ điều gì…"
    }

    private var contextualSuggestionLabel: String {
        contextualWorkout?.status == .done || contextualActivity != nil ? "REVIEW WORKOUT" : "EDIT WORKOUT"
    }

    private var contextualSuggestionPrompts: [String] {
        if contextualActivity != nil {
            return [
                "Review this run against the planned target.",
                "What should I adjust next after this run?"
            ]
        }
        guard let workout = contextualWorkout else { return [] }
        if workout.status == .done {
            return [
                "Review this completed workout.",
                "What should I adjust next after this run?"
            ]
        }
        if workout.isScheduleLocked || workout.kind == .race {
            return [
                "Review why this workout is fixed.",
                "Ask Coach for safe alternatives."
            ]
        }
        return [
            "Change distance or duration",
            "Move this workout"
        ]
    }

    private var contextualEyebrow: String {
        if contextualActivity != nil { return "Review with Coach" }
        if contextualWorkout?.status == .done || contextualWorkout?.isScheduleLocked == true || contextualWorkout?.kind == .race { return "Review with Coach" }
        return "Editing workout"
    }

    private var contextualTitle: String {
        if let workout = contextualWorkout { return workout.kind?.displayName ?? "Run" }
        if let activity = contextualActivity {
            return Formatters.kilometers(activity.distanceMeters).isEmpty ? "Completed run" : "Completed run"
        }
        return "Workout unavailable"
    }

    private var contextualDateText: String {
        if let workout = contextualWorkout {
            return workout.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        if let activity = contextualActivity {
            return activity.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        return "Return to Calendar"
    }

    private var contextualSymbolName: String {
        contextualWorkout?.kind?.symbolName ?? "figure.run"
    }

    private var contextualMetricPairs: [(String, String)] {
        if let workout = contextualWorkout {
            var pairs = [("Distance", Formatters.kilometers(workout.distanceKm * 1000))]
            if let duration = workout.expectedDurationSeconds {
                pairs.append(("Duration", Formatters.duration(duration)))
            }
            if let pace = workout.paceBand {
                pairs.append(("Pace", Formatters.paceBand(pace)))
            }
            return pairs
        }
        if let activity = contextualActivity {
            return [
                ("Distance", Formatters.kilometers(activity.distanceMeters)),
                ("Duration", Formatters.duration(activity.durationSeconds)),
                ("Pace", Formatters.pace(activity.avgPaceSecondsPerKm))
            ]
        }
        return [("Status", "Unavailable")]
    }

    private var contextualAccessibilityLabel: String {
        "\(contextualEyebrow): \(contextualTitle), \(contextualDateText)"
    }

    private var compactContextChip: some View {
        HStack(spacing: 7) {
            Image(systemName: contextualSymbolName)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text("\(contextualTitle) · \(contextualDateText)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(Theme.accentSoft, in: Capsule())
        .accessibilityLabel("Workout context: \(contextualTitle), \(contextualDateText)")
    }

    private var fixedContextChip: some View {
        HStack(spacing: 6) {
            Image(systemName: contextualSymbolName)
                .font(.caption.weight(.semibold))
            Text(contextualTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "lock.fill")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(Theme.chip, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityLabel("Fixed workout context: \(contextualTitle)")
    }

    private var currentAttachments: [CoachContextAttachment] {
        var attachments: [CoachContextAttachment] = []
        if evidence.readinessSnapshot {
            attachments.append(.health)
        }
        if let contextualWorkoutID {
            attachments.append(.plannedWorkout(contextualWorkoutID))
        } else if let contextualCompletedActivityID {
            attachments.append(.completedActivity(contextualCompletedActivityID))
        } else {
            switch evidence.workout {
            case .planned(let uuid):
                attachments.append(.plannedWorkout(uuid))
            case .completed(let uuid):
                attachments.append(.completedActivity(uuid))
            case nil:
                break
            }
        }
        if let selectedImageAttachment {
            attachments.append(.image(selectedImageAttachment))
        }
        return attachments
    }


    private func loadImageAttachment(from item: PhotosPickerItem?) {
        guard let item else {
            clearImageAttachment()
            return
        }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let compressed = compressedImageData(from: data),
                  let image = UIImage(data: compressed) else { return }
            await MainActor.run {
                selectedImageAttachment = CoachImageAttachment(
                    data: compressed,
                    mediaType: "image/jpeg",
                    filename: "training-context.jpg"
                )
                selectedImage = image
                evidence.hasPhoto = true
            }
        }
    }

    private func compressedImageData(from data: Data) -> Data? {
        guard var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let maxSide: CGFloat = 1280
        let largestSide = max(image.extent.width, image.extent.height)
        let scale = largestSide > maxSide ? maxSide / largestSide : 1
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.78
        ]
        return CIContext().jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: options)
    }

    private func clearImageAttachment() {
        selectedPhotoItem = nil
        selectedImageAttachment = nil
        selectedImage = nil
        evidence.hasPhoto = false
    }

    private func updateKeyboardHeight(from notification: Notification, forceHidden: Bool = false) {
        guard !forceHidden,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            withKeyboardAnimation(notification) { softwareKeyboardHeight = 0 }
            return
        }
        let screenMaxY = UIScreen.main.bounds.maxY
        let overlap = max(0, screenMaxY - frame.minY)
        withKeyboardAnimation(notification) { softwareKeyboardHeight = overlap }
    }

    private func withKeyboardAnimation(_ notification: Notification, updates: @escaping () -> Void) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.2
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeOut(duration: duration)) { updates() }
        }
    }

    private func isPlanAuditMessage(_ message: ChatMessage) -> Bool {
        message.role == .assistant && message.appliedAdjustment != nil && message.text.hasPrefix("Applied:")
    }
}

private struct ChatScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SavedPromptsSheet: View {
    let prompts: [String]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Câu hỏi đã lưu")
                        .font(.torHeading(20, .bold))
                        .foregroundStyle(Theme.text)
                    Text("Chọn một câu, rồi sửa trước khi gửi.")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 36, height: 36)
                        .background(Theme.chip, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng")
            }

            VStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button {
                        onSelect(prompt)
                    } label: {
                        HStack(spacing: 10) {
                            Text(prompt)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Spacer()
                            Image(systemName: "arrow.turn.down.left")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.faint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chèn câu hỏi đã lưu: \(prompt)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
    }
}

private struct ChatHistorySheet: View {
    let threads: [ChatThread]
    let activeThreadID: UUID?
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var threadBeingRenamed: ChatThread?
    @State private var renameDraft = ""

    private var visibleThreads: [ChatThread] {
        threads
            .filter { $0.archivedAt == nil }
            .sorted { lhs, rhs in
                switch (lhs.pinnedAt, rhs.pinnedAt) {
                case let (l?, r?): return l > r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.updatedAt > rhs.updatedAt
                }
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if visibleThreads.isEmpty {
                    ContentUnavailableView(
                        "Chưa có chat",
                        systemImage: "message",
                        description: Text("Các cuộc trò chuyện với Coach sẽ hiện ở đây.")
                    )
                    .foregroundStyle(Theme.text, Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(visibleThreads) { thread in
                        chatRow(thread)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    archive(thread)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(Theme.warn)
                            }
                            .contextMenu {
                                Button {
                                    togglePin(thread)
                                } label: {
                                    Label(thread.pinnedAt == nil ? "Ghim chat" : "Bỏ ghim", systemImage: thread.pinnedAt == nil ? "pin" : "pin.slash")
                                }
                                Button {
                                    beginRename(thread)
                                } label: {
                                    Label("Đổi tên", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    archive(thread)
                                } label: {
                                    Label("Lưu trữ", systemImage: "archivebox")
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .alert("Đổi tên chat", isPresented: renameAlertBinding) {
                TextField("Tên chat", text: $renameDraft)
                Button("Hủy", role: .cancel) { clearRenameDraft() }
                Button("Lưu") { saveRename() }
            } message: {
                Text("Đặt tên để nhận ra cuộc trò chuyện này sau.")
            }
        }
        .presentationBackground(Theme.bg)
        .presentationDragIndicator(.visible)
    }

    private func chatRow(_ thread: ChatThread) -> some View {
        HStack(spacing: 10) {
            Button {
                onSelect(thread.uuid)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: thread.uuid == activeThreadID ? "message.fill" : "message")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if thread.pinnedAt != nil {
                                Image(systemName: "pin.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityLabel("Đã ghim")
                            }
                            Text(title(for: thread))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }
                        Text(relativeDate(for: thread.updatedAt))
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }

                    Spacer(minLength: 8)

                    if thread.uuid == activeThreadID {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.good)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    togglePin(thread)
                } label: {
                    Label(thread.pinnedAt == nil ? "Ghim chat" : "Bỏ ghim", systemImage: thread.pinnedAt == nil ? "pin" : "pin.slash")
                }
                Button {
                    beginRename(thread)
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    archive(thread)
                } label: {
                    Label("Lưu trữ", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 36, height: 36)
                    .background(Theme.chip, in: Circle())
            }
            .accessibilityLabel("Tùy chọn chat")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(thread.pinnedAt == nil ? Theme.border : Theme.accent.opacity(0.28), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { threadBeingRenamed != nil },
            set: { isPresented in
                if !isPresented { clearRenameDraft() }
            }
        )
    }

    private func togglePin(_ thread: ChatThread) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        thread.pinnedAt = thread.pinnedAt == nil ? .now : nil
        thread.updatedAt = .now
        try? modelContext.save()
    }

    private func archive(_ thread: ChatThread) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        thread.archivedAt = .now
        thread.pinnedAt = nil
        try? modelContext.save()
    }

    private func beginRename(_ thread: ChatThread) {
        threadBeingRenamed = thread
        renameDraft = title(for: thread)
    }

    private func saveRename() {
        guard let thread = threadBeingRenamed else { return }
        let clean = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        thread.title = clean.isEmpty ? "New chat" : clean
        thread.updatedAt = .now
        try? modelContext.save()
        clearRenameDraft()
    }

    private func clearRenameDraft() {
        threadBeingRenamed = nil
        renameDraft = ""
    }

    private func title(for thread: ChatThread) -> String {
        let clean = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "New chat" : clean
    }

    private func relativeDate(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct PendingCoachSend: Identifiable {
    let id = UUID()
    let text: String
    let attachments: [CoachContextAttachment]
    let evidence: EvidenceSelection
    var reviewedSnapshot: GroundingSnapshot? = nil
    var interactionId: String? = nil
    var selectedOptionId: String? = nil
    var isCustomInteractionResponse = false
    var interactionMessageID: UUID? = nil
}

private struct EvidenceReviewPresentation: Identifiable {
    let id = UUID()
    let snapshot: GroundingSnapshot
    let pendingSend: PendingCoachSend?
}

private struct PendingOtherCoachResponse: Equatable {
    var messageID: UUID
    var interactionID: String
    var placeholder: String
}

private enum ChatPlanRetry: Equatable {
    case replacement(PendingWorkoutReplacement)
    case proposal(PendingPlanProposal)
}

private enum ChatPlanUndo: Equatable {
    case safe
    case unsafe
}

private enum ChatPlanTransaction: Equatable {
    case applying(title: String)
    case success(summary: String, date: Date?, undo: ChatPlanUndo)
    case failure(userMessage: String, technicalDetails: String, retry: ChatPlanRetry)

    var calendarDate: Date? {
        if case .success(_, let date, _) = self { return date }
        return nil
    }
}

private extension String {
    var stableSuggestionID: String {
        let folded = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let characters = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(characters)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "suggestion" : collapsed
    }

    var containsTomorrowReference: Bool {
        let lower = lowercased()
        return lower.contains("ngày mai")
            || lower.contains("ngay mai")
            || lower.contains("tomorrow")
            || lower.contains("tmr")
            || lower.contains("mai tập")
            || lower.contains("mai chay")
            || lower.contains("mai chạy")
    }

    var requestedDistanceKmText: String? {
        let pattern = #"(?i)(\d+(?:[\.,]\d+)?)\s*(?:km|kilometer|kilometre|cây|cay)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        let value = self[valueRange].replacingOccurrences(of: ",", with: ".")
        return "\(value) km"
    }

    var requestsTimeSuggestion: Bool {
        let lower = lowercased()
        return lower.contains("giờ")
            || lower.contains("gio")
            || lower.contains("time")
            || lower.contains("when")
            || lower.contains("lúc nào")
            || lower.contains("luc nao")
            || lower.contains("find")
    }

    var requestsScheduleMove: Bool {
        let lower = lowercased()
        return lower.contains("đổi")
            || lower.contains("doi")
            || lower.contains("cập nhật")
            || lower.contains("cap nhat")
            || lower.contains("update")
            || lower.contains("move")
            || lower.contains("schedule")
    }
}

private struct PlanTransactionCard: View {
    let transaction: ChatPlanTransaction
    let onViewCalendar: () -> Void
    let onUndo: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var showsTechnicalDetails = false

    var body: some View {
        TorCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                switch transaction {
                case .applying(let title):
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.accent)
                        Text(title)
                            .font(.torHeading(15, .bold))
                            .foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                case .success(let summary, let date, let undo):
                    Label("Đã cập nhật kế hoạch", systemImage: "checkmark.circle.fill")
                        .font(.torHeading(15, .bold))
                        .foregroundStyle(Theme.good)
                    Text(summary.replacingOccurrences(of: "Applied: ", with: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    if let date {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.dim)
                    }
                    HStack(spacing: 8) {
                        transactionButton("Xem trong lịch", systemImage: "calendar", prominent: true, action: onViewCalendar)
                        if undo == .safe {
                            transactionButton("Hoàn tác", systemImage: "arrow.uturn.backward", prominent: false, action: onUndo)
                        }
                    }
                case .failure(let userMessage, let technicalDetails, _):
                    Label(failureTitle(for: userMessage), systemImage: "exclamationmark.triangle.fill")
                        .font(.torHeading(15, .bold))
                        .foregroundStyle(Theme.warn)
                    Text(userMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        transactionButton("Thử lại", systemImage: "arrow.clockwise", prominent: true, action: onRetry)
                        transactionButton("Giữ kế hoạch cũ", systemImage: "xmark", prominent: false, action: onDismiss)
                    }
                    DisclosureGroup("Xem chi tiết kỹ thuật", isExpanded: $showsTechnicalDetails) {
                        Text(technicalDetails)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.faint)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }

    private func failureTitle(for message: String) -> String {
        if message.contains("thiếu") { return "Chưa thể tạo buổi chạy" }
        if message.contains("tải tập") { return "Thay đổi này chưa phù hợp với kế hoạch hiện tại" }
        return "Chưa thể cập nhật kế hoạch lúc này"
    }

    private func transactionButton(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.torHeading(13, .bold))
                .foregroundStyle(prominent ? .white : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(prominent ? Theme.accent : Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(prominent ? .clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ContextualWorkoutMetricChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.torMono(11, .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension ChatThread {
    func isStale(comparedTo snapshot: WorkoutCoachContext) -> Bool {
        guard let previous = WorkoutCoachContext.decode(contextualSnapshotJSON) else { return false }
        return previous.workoutId != snapshot.workoutId
            || previous.completedActivityId != snapshot.completedActivityId
            || previous.calendarDate != snapshot.calendarDate
            || previous.workoutType != snapshot.workoutType
            || previous.plannedDistanceKm != snapshot.plannedDistanceKm
            || previous.plannedDurationSeconds != snapshot.plannedDurationSeconds
            || previous.plannedPaceFastSecondsPerKm != snapshot.plannedPaceFastSecondsPerKm
            || previous.plannedPaceSlowSecondsPerKm != snapshot.plannedPaceSlowSecondsPerKm
            || previous.workoutStatus != snapshot.workoutStatus
    }
}

private struct GroundingReviewSheet: View {
    let snapshot: GroundingSnapshot
    let requiresConfirmation: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nguồn dữ liệu đã sử dụng")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(snapshot.footnoteLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TorCard(padding: 14, cornerRadius: 16) {
                        Text(snapshot.summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if requiresConfirmation {
                        Button(action: onConfirm) {
                            Label("Dùng nguồn dữ liệu và gửi", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                if requiresConfirmation {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Hủy", action: onCancel)
                    }
                }
                if !requiresConfirmation {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Xong", action: onConfirm)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }
}
