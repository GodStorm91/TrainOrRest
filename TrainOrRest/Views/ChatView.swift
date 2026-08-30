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
    @State private var showsContextSheet = false
    @State private var isChatListPresented = false
    @State private var isSavedPromptsPresented = false
    @State private var isProviderSettingsPresented = false
    @State private var isHeaderCollapsed = false
    @State private var headerHeight: CGFloat = CoachHeaderMetrics.fallbackHeaderHeight
    @State private var softwareKeyboardHeight: CGFloat = 0
    @State private var planTransaction: ChatPlanTransaction?
    @State private var lastConsumedReviewRequestID: String?
    @State private var submittingPromptSuggestionKeys = Set<String>()
    @State private var submittingFollowUpMessageID: UUID?
    @State private var submittingInteractionID: String?
    @State private var pendingOtherResponse: PendingOtherCoachResponse?
    @State private var draftActionTypeOverride: CoachRequestActionType?
    @State private var draftActionTypeOverridePrompt: String?
    @State private var scrollState = ChatScrollState()
    @State private var chatViewportHeight: CGFloat = 0
    @State private var bottomAnchorMaxY: CGFloat = 0
    @State private var pendingScrollWorkItem: DispatchWorkItem?
    @State private var hasPositionedInitialThread = false
    @FocusState private var composerFocused: Bool
    @AppStorage("coachEvidenceReviewed") private var coachEvidenceReviewed = false
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private let calendar = Calendar.current
    private let bottomAnchorID = "chat-feed-bottom-anchor"
    private let nearBottomThreshold: CGFloat = 110

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
        return allMessages.filter { message in
            message.threadID == activeThreadID && isVisibleConversationMessage(message)
        }
    }

    private var isSoftwareKeyboardVisible: Bool { softwareKeyboardHeight > 80 }
    private var isContextualSession: Bool { contextualWorkoutID != nil || contextualCompletedActivityID != nil }
    private var messageTopInset: CGFloat {
        CoachHeaderMetrics.messageTopInset(headerHeight: headerHeight)
    }

    private var contextSourceCount: Int {
        var n = 0
        if isContextualSession { n += 1 }
        if evidence.readinessSnapshot { n += 1 }
        if evidence.workout != nil { n += 1 }
        if selectedImageAttachment != nil { n += 1 }
        return n
    }


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
                        .padding(.top, messageTopInset)
                } else if messages.isEmpty {
                    emptyState
                        .padding(.top, messageTopInset)
                } else {
                    messageFeed
                        .padding(.top, messageTopInset)
                }
                if hasAPIKey {
                    chatFooter
                }
            }

            topControlDeck
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: CoachHeaderHeightKey.self, value: proxy.size.height)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .onPreferenceChange(CoachHeaderHeightKey.self) {
            headerHeight = $0
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: true)
            runAppearSetup()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: false)
        }
        .onChange(of: allMessages.count) {
            attachUnthreadedMessagesToActiveThread()
        }
        .onChange(of: chatStore.generationState) { _, state in
            if case .completed = state {
                UIAccessibility.post(notification: .announcement, argument: language.responseCompleteAnnouncement)
            }
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
                language: language,
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
            ChatHistorySheet(threads: chatThreads, activeThreadID: chatSession.activeThreadID, language: language) { threadID in
                chatSession.activeThreadID = threadID
                isChatListPresented = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isSavedPromptsPresented) {
            SavedPromptsSheet(prompts: savedPrompts, language: language) { prompt in
                draft = prompt
                composerFocused = true
                isSavedPromptsPresented = false
            }
            .presentationDetents([.height(310), .medium])
        }
        .sheet(isPresented: $isProviderSettingsPresented) {
            NavigationStack {
                CoachProviderSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(language.doneLabel) { isProviderSettingsPresented = false }
                        }
                    }
            }
        }
    }

    private func runAppearSetup() {
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

    private func checkMutationStatus() {
        if isContextualSession {
            dismiss()
        } else {
            onOpenCalendar(nil)
        }
    }

    private func chooseDataAgain(_ failedTurn: ChatMessage) {
        let restoredPrompt = precedingUserPrompt(for: failedTurn)
        chatStore.dismissFailedResponse(failedTurn.turnID, in: modelContext)
        evidence = EvidenceSelection()
        clearImageAttachment()
        if let restoredPrompt { draft = restoredPrompt }
        composerFocused = true
    }

    private func precedingUserPrompt(for assistant: ChatMessage) -> String? {
        let candidate: ChatMessage?
        if let parentID = assistant.parentUserTurnID {
            candidate = allMessages.first { $0.turnID == parentID && $0.role == .user }
        } else {
            let ordered = allMessages
                .filter { $0.threadID == assistant.threadID }
                .sorted { $0.date < $1.date }
            candidate = ordered.prefix(while: { $0.turnID != assistant.turnID })
                .last { $0.role == .user }
        }
        let text = candidate?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
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
            .accessibilityLabel(isContextualSession ? language.backToCalendarLabel : language.openMenuLabel)

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
                        Label(language.newConversationLabel, systemImage: "square.and.pencil")
                    }
                    Button { isChatListPresented = true } label: {
                        Label(language.chatHistoryLabel, systemImage: "clock.arrow.circlepath")
                    }
                }
                NavigationLink { SettingsView() } label: {
                    Label(language.settingsLabel, systemImage: "gearshape")
                }
            } label: {
                Image(systemName: isHeaderCollapsed ? "ellipsis" : "square.and.pencil")
                    .torTopControlIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isContextualSession ? language.coachOptionsLabel : language.newConversationLabel)
        }
        .frame(minHeight: isHeaderCollapsed ? 44 : 52)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .torGlass(cornerRadius: isHeaderCollapsed ? 22 : 24, tint: .subtle)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHeaderCollapsed)
    }

    private var headerSubtitle: String? {
        if let workout = contextualWorkout {
            let verb = workout.status == .planned && !workout.isScheduleLocked && workout.kind != .race ? language.editingWorkoutStatus : language.reviewWithCoachStatus
            return "\(verb) · \(workout.kind?.displayName ?? "Run") · \(workout.date.formatted(.dateTime.month(.abbreviated).day().locale(language.uiLocale)))"
        }
        if let activity = contextualActivity {
            let distance = Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: "")
            return "\(language.reviewWithCoachStatus) · \(distance) · \(activity.date.formatted(.dateTime.month(.abbreviated).day().locale(language.uiLocale)))"
        }
        if let updated = latestGroundingTimeText {
            return language.dataUpdatedAt(updated)
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
                    Text(language.coachRoleLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
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
                        .foregroundStyle(Theme.data)
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
                        Label(language.viewWorkoutDetailsLabel, systemImage: "doc.text.magnifyingglass")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.openWorkoutDetailsLabel)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(contextualAccessibilityLabel)
    }

    private var contextualPromptRows: some View {
        VStack(spacing: 9) {
            ForEach(visibleContextualPromptSuggestions.prefix(2)) { suggestion in
                ChatPromptButton(suggestion.prompt, systemImage: suggestion.prompt == language.moveThisWorkoutPrompt ? "calendar.badge.clock" : "sparkles") {
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
                    Image(systemName: todayVerdictSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(todayReadinessTint)
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
                    .foregroundStyle(Theme.data)
                    .frame(width: 24, height: 24)
                    .background(Theme.data.opacity(0.12), in: Circle())
                Text(todayPlannedWorkoutText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            Button { draft = language.viewTodayPlanLabel } label: {
                HStack(spacing: 8) {
                    Text(language.viewTodayPlanLabel)
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
                            onCheckStatus: { checkMutationStatus() },
                            onChooseDataAgain: { failed in chooseDataAgain(failed) },
                            onCheckConnection: { isProviderSettingsPresented = true },
                            actionableInteractionID: newestPendingInteractionID,
                            isSubmittingInteraction: submittingInteractionID == message.interaction?.id,
                            processingStage: processingStage(for: message),
                            onSelectInteractionOption: selectInteractionOption,
                            onSelectInteractionOther: selectInteractionOther,
                            onSelectFollowUp: selectFollowUp
                        )
                        .id(message.turnID)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ChatBottomAnchorPreferenceKey.self,
                                    value: geometry.frame(in: .named("chatFeed")).maxY
                                )
                            }
                        )
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .coordinateSpace(name: "chatFeed")
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: ChatViewportHeightPreferenceKey.self, value: geometry.size.height)
                }
            )
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
            .onPreferenceChange(ChatViewportHeightPreferenceKey.self) { height in
                chatViewportHeight = height
                updateNearBottomState()
            }
            .onPreferenceChange(ChatBottomAnchorPreferenceKey.self) { maxY in
                bottomAnchorMaxY = maxY
                updateNearBottomState()
                guard messages.isEmpty == false else { return }
                if scrollState.isFollowingStream && !scrollState.isUserDragging {
                    scheduleScrollToBottom(proxy, animated: false)
                } else if !scrollState.isNearBottom, chatStore.isSending {
                    scrollState.hasUnseenContent = true
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        scrollState.isUserDragging = true
                        if value.translation.height > 12 || !scrollState.isNearBottom {
                            scrollState.isFollowingStream = false
                        }
                    }
                    .onEnded { _ in
                        scrollState.isUserDragging = false
                        if scrollState.isNearBottom {
                            scrollState.isFollowingStream = true
                            scrollState.hasUnseenContent = false
                        }
                    }
            )
            .onAppear {
                positionInitialConversation(proxy)
            }
            .onChange(of: messages.count) {
                if hasPositionedInitialThread {
                    if scrollState.isFollowingStream || scrollState.isNearBottom {
                        scheduleScrollToBottom(proxy, animated: scrollState.isFollowingStream && !reduceMotion)
                    } else if chatStore.isSending {
                        scrollState.hasUnseenContent = true
                    }
                } else {
                    positionInitialConversation(proxy)
                }
            }
            .onChange(of: chatStore.isSending) {
                if chatStore.isSending {
                    if scrollState.isNearBottom {
                        scrollState.isFollowingStream = true
                        scheduleScrollToBottom(proxy, animated: false)
                    }
                } else if scrollState.isFollowingStream {
                    scheduleScrollToBottom(proxy, animated: !reduceMotion)
                }
            }
            .onChange(of: chatSession.activeThreadID) {
                hasPositionedInitialThread = false
                scrollState = ChatScrollState()
                positionInitialConversation(proxy)
            }
            .onChange(of: softwareKeyboardHeight) {
                if scrollState.isNearBottom || scrollState.isFollowingStream {
                    scheduleScrollToBottom(proxy, animated: false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .torChatContinueAnswerRequested)) { _ in
                scrollState.isFollowingStream = true
                scrollState.hasUnseenContent = false
                scheduleScrollToBottom(proxy, animated: !reduceMotion)
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

    private func positionInitialConversation(_ proxy: ScrollViewProxy) {
        guard !messages.isEmpty else { return }
        DispatchQueue.main.async {
            scrollToBottom(proxy, animated: false)
            hasPositionedInitialThread = true
            scrollState.isNearBottom = true
            scrollState.isFollowingStream = true
            scrollState.hasUnseenContent = false
        }
    }

    private func scheduleScrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard messages.isEmpty == false, !scrollState.isUserDragging else { return }
        pendingScrollWorkItem?.cancel()
        let work = DispatchWorkItem {
            scrollToBottom(proxy, animated: animated)
        }
        pendingScrollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !messages.isEmpty else { return }
        let action = { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { action() }
            } else {
                action()
            }
        }
    }

    private func updateNearBottomState() {
        guard chatViewportHeight > 0 else { return }
        let distance = bottomAnchorMaxY - chatViewportHeight
        let near = distance <= nearBottomThreshold
        scrollState.isNearBottom = near
        if near && !scrollState.isUserDragging {
            scrollState.isFollowingStream = true
            scrollState.hasUnseenContent = false
        }
    }

    private var missingKeyView: some View {
        ContentUnavailableView {
            Label(language.apiKeyNeededTitle, systemImage: "key")
        } description: {
            Text(language.apiKeyNeededMessage(provider: CoachModelProvider.displayName(for: model)))
        } actions: {
            NavigationLink(language.addApiKeyLabel) {
                CoachProviderSettingsView()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var chatFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if scrollState.hasUnseenContent {
                continueAnswerButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let transaction = planTransaction {
                PlanTransactionCard(
                    transaction: transaction,
                    language: language,
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
                    label: language.matchedWorkoutLabel
                ) { prompt in
                    draft = prompt
                    composerFocused = true
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: replacementCoordinator.pending)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: replacementCoordinator.pendingProposal)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isSoftwareKeyboardVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: scrollState.hasUnseenContent)
    }

    private var continueAnswerButton: some View {
        Button {
            scrollState.isFollowingStream = true
            scrollState.hasUnseenContent = false
            NotificationCenter.default.post(name: .torChatContinueAnswerRequested, object: nil)
        } label: {
            Label(language.continueAnswerLabel, systemImage: "arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Theme.accentSoft, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.continueAnswerLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var shouldShowContextualSuggestions: Bool {
        isContextualSession
            && !hasPendingInteraction
            && !hasActiveInlineFailure
            && !isSoftwareKeyboardVisible
            && !chatStore.isSending
            && !replacementCoordinator.hasPendingDecision
            && !replacementCoordinator.isConfirming
            && messages.count <= 2
            && !visibleContextualPromptSuggestions.isEmpty
    }

    private var shouldShowDraftRelativeDateSuggestions: Bool {
        !draftRelativeDateSuggestions.isEmpty
            && !hasActiveInlineFailure
            && !chatStore.isSending
            && !replacementCoordinator.hasPendingDecision
            && !replacementCoordinator.isConfirming
    }

    private var draftRelativeDateSuggestions: [String] {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3, clean.containsTomorrowReference else { return [] }

        guard let workout = tomorrowWorkout else {
            return [language.noTomorrowWorkoutSuggestion]
        }

        let workoutText = "\(workout.kind?.displayName ?? "Workout") · \(kmText(workout.distanceKm))"
        if let requestedKm = clean.requestedDistanceKmText {
            return [language.changeTomorrowDistanceSuggestion(workout: workoutText, distance: requestedKm)]
        }

        if clean.requestsTimeSuggestion {
            return [language.findTimeTomorrowSuggestion(workout: workoutText)]
        }

        if clean.requestsScheduleMove {
            return [language.moveTomorrowSuggestion(workout: workoutText)]
        }

        return [language.updateTomorrowSuggestion(workout: workoutText)]
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

    private var hasActiveInlineFailure: Bool {
        messages.contains { message in
            message.role == .assistant
                && [.failed, .retrying, .reconciling].contains(message.assistantStatus)
        }
    }

    private func processingStage(for message: ChatMessage) -> CoachProcessingStage? {
        guard chatStore.generationState.messageId == message.turnID else { return nil }
        if case .processing(_, let stage) = chatStore.generationState {
            return stage
        }
        return nil
    }

    private var visibleContextualPromptSuggestions: [CoachPromptSuggestion] {
        guard let conversationId = chatSession.activeThreadID else { return [] }
        let workoutId = contextualWorkoutID ?? contextualCompletedActivityID
        let candidates = contextualSuggestionPrompts.enumerated().map { index, prompt in
            CoachPromptSuggestion(
                id: "context-\(index)",
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
        let ids = ["explain-today", "review-workout", "propose-edit"]
        let candidates = zip(ids, language.openingPrompts).map { id, prompt in
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
        if id.contains("review-workout") { return "waveform.path.ecg" }
        if id.contains("propose-edit") { return "calendar.badge.clock" }
        return "questionmark.circle"
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Menu {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(language.attachImageLabel, systemImage: "photo")
                }
                Button { evidence.readinessSnapshot = true } label: {
                    Label(language.healthDataChipLabel, systemImage: "heart")
                }
                Button { attachLatestWorkout() } label: {
                    Label(language.workoutMenuLabel, systemImage: "figure.run")
                }
                Button { isSavedPromptsPresented = true } label: {
                    Label(language.savedQuestionsLabel, systemImage: "bookmark")
                }
                .accessibilityLabel(language.openSavedQuestionsLabel)
                if selectedImageAttachment != nil {
                    Button(role: .destructive) { clearImageAttachment() } label: {
                        Label(language.removeImageLabel, systemImage: "xmark.circle")
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
            .accessibilityLabel(language.attachEvidenceLabel)
            if contextSourceCount > 0 {
                CoachSourceIndicator(count: contextSourceCount, language: language) {
                    showsContextSheet = true
                }
            }


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
                .accessibilityLabel(language.hideKeyboardLabel)
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
            .accessibilityLabel(language.sendMessageLabel)
            .disabled(isSendDisabled)
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .torGlass(cornerRadius: 26, tint: .graphite)
        .sheet(isPresented: $showsContextSheet) {
            NavigationStack {
                ScrollView {
                    ChatContextTrayView(
                        evidence: $evidence,
                        selectedPhotoItem: $selectedPhotoItem,
                        selectedImageAttachment: $selectedImageAttachment,
                        selectedImage: $selectedImage,
                        plannedWorkouts: plannedWorkouts,
                        completedActivities: completedActivities,
                        onReviewEvidence: { showsContextSheet = false }
                    )
                    .padding(16)
                }
                .navigationTitle(language.contextSourcesSheetTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.coachDetailDoneLabel) {
                            showsContextSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var savedPrompts: [String] { language.savedPrompts }

    private func attachLatestWorkout() {
        if let activity = completedActivities.first {
            evidence.workout = .completed(activity.hkUUID)
        } else if let workout = plannedWorkouts.first(where: { $0.date >= calendar.startOfDay(for: .now) }) {
            evidence.workout = .planned(workout.uuid)
        } else {
            draft = language.chooseRecentWorkoutPrompt
            composerFocused = true
        }
    }

    private var isSendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || chatStore.isSending
            || (replacementCoordinator.hasPendingDecision && pendingOtherResponse == nil)
            || replacementCoordinator.isConfirming
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

    private var todayVerdictSymbol: String {
        switch todayReadiness?.verdict {
        case .train: return "figure.run"
        case .goEasy: return "tortoise"
        case .rest: return "moon.zzz"
        case .insufficientData: return "chart.line.uptrend.xyaxis"
        case .none: return "ellipsis"
        }
    }

    private var todayReadinessTitle: String {
        language.todayReadinessTitle(todayReadiness?.verdict)
    }

    private var todayReadinessSubtitle: String {
        guard let readiness = todayReadiness else { return language.noReadinessSubtitle }
        if readiness.reasons.isEmpty {
            return readiness.verdict == .train ? language.goodRecoverySubtitle : readiness.verdict.torSubtitle
        }
        return Array(readiness.reasons.prefix(2)).joined(separator: " · ")
    }

    private var todayPlannedWorkoutText: String {
        guard let workout = todayWorkout else { return language.noPlannedWorkoutTodayText }
        var parts: [String] = []
        parts.append(workout.kind?.displayName ?? "Run")
        parts.append(kmText(workout.distanceKm))
        if let band = workout.paceBand {
            parts.append(Formatters.paceBand(band).replacingOccurrences(of: " /km", with: "/km"))
        }
        return language.plannedWorkoutPrefix + parts.joined(separator: " · ")
    }

    private func kmText(_ km: Double) -> String {
        abs(km.rounded() - km) < 0.05 ? "\(Int(km.rounded())) km" : String(format: "%.1f km", km)
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
            interactionMessageID: pendingOtherResponse?.messageID,
            actionTypeOverride: draft == draftActionTypeOverridePrompt ? draftActionTypeOverride : nil,
            focusComposerAfterSend: false
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
        draftActionTypeOverride = nil
        draftActionTypeOverridePrompt = nil
        pendingOtherResponse = nil
        evidence = isContextualSession ? contextualEvidenceSelection : EvidenceSelection()
        clearImageAttachment()
        composerFocused = pending.focusComposerAfterSend
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
                actionTypeOverride: pending.actionTypeOverride,
                expectedResponseInteraction: pending.expectedResponseInteraction,
                displayText: pending.displayText,
                contextSnapshotId: pending.contextSnapshotId,
                contextItems: pending.contextItems,
                in: modelContext
            )
            await MainActor.run {
                if !didSend, let previousInteraction, let messageID = pending.interactionMessageID {
                    chatStore.restoreInteraction(messageID: messageID, interaction: previousInteraction, in: modelContext)
                }
                composerFocused = pending.focusComposerAfterSend
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
            composerFocused = pending.focusComposerAfterSend
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
            actionTypeOverride: pending.actionTypeOverride,
            expectedResponseInteraction: pending.expectedResponseInteraction,
            displayText: pending.displayText,
            contextSnapshotId: pending.contextSnapshotId,
            contextItems: pending.contextItems,
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
            text: option.submissionText,
            attachments: currentAttachments,
            evidence: evidence,
            interactionId: interaction.id,
            selectedOptionId: option.id,
            interactionMessageID: message.turnID,
            displayText: option.visibleSelectionText
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

    private func selectFollowUp(_ message: ChatMessage, option: CoachChoiceOption) {
        guard submittingFollowUpMessageID == nil, !message.followUpsConsumed else { return }
        submittingFollowUpMessageID = message.turnID
        message.followUpsConsumed = true
        try? modelContext.save()
        let pending = PendingCoachSend(
            text: option.submissionText,
            attachments: currentAttachments,
            evidence: evidence,
            displayText: option.visibleSelectionText
        )
        Task {
            let didSend = await sendAlreadyReviewed(pending)
            await MainActor.run {
                submittingFollowUpMessageID = nil
                if !didSend {
                    message.followUpsConsumed = false
                    try? modelContext.save()
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
        planTransaction = .applying(title: language.updatingPlanTitle)
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
        planTransaction = .applying(title: language.updatingPlanTitle)
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
            return language.planErrorMissingTargets
        }
        if lower.contains("load") || lower.contains("volume") || lower.contains("ramp") || lower.contains("safe") {
            return language.planErrorLoadTooHigh
        }
        return language.planUnchangedMessage
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
                    interactionMessageID: $0.interactionMessageID,
                    actionTypeOverride: $0.actionTypeOverride,
                    expectedResponseInteraction: $0.expectedResponseInteraction,
                    displayText: $0.displayText,
                    contextSnapshotId: $0.contextSnapshotId,
                    contextItems: $0.contextItems,
                    focusComposerAfterSend: $0.focusComposerAfterSend
                )
            }
            evidenceReview = EvidenceReviewPresentation(snapshot: snapshot, pendingSend: pendingWithSnapshot)
        } catch {
            chatStore.presentError(error.coachTechnicalDescription)
        }
    }

    private func createOrResumeContextualThread() {
        guard let snapshot = currentWorkoutCoachContext else {
            chatStore.presentError(language.workoutNoLongerAvailableError)
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
        let date = snapshot.calendarDate.formatted(.dateTime.month(.abbreviated).day().locale(language.uiLocale))
        let prefix = snapshot.workoutStatus == .completed ? language.reviewTitlePrefix : language.editTitlePrefix
        return "\(prefix) \(snapshot.workoutTitle) · \(date)"
    }

    private func consumeReviewRequestIfNeeded() {
        guard let request = reviewRequest, lastConsumedReviewRequestID != request.id else { return }
        lastConsumedReviewRequestID = request.id
        guard let activityUUID = request.activityUUID else {
            let threadID = createNewThread(title: request.threadTitle)
            evidence = EvidenceSelection(readinessSnapshot: true, weekPlan: true, workout: nil, hasPhoto: false)
            chatSession.activeThreadID = threadID
            onReviewRequestConsumed(request)
            if request.autoSubmit {
                composerFocused = false
                let pending = PendingCoachSend(
                    text: request.prompt,
                    attachments: currentAttachments,
                    evidence: evidence,
                    actionTypeOverride: request.actionTypeOverride,
                    expectedResponseInteraction: request.expectedResponseInteraction,
                    displayText: request.displayText,
                    contextSnapshotId: request.contextSnapshotId,
                    contextItems: request.contextItems,
                    focusComposerAfterSend: request.shouldFocusComposer
                )
                Task {
                    _ = await sendAlreadyReviewed(pending)
                }
            } else {
                draft = request.displayText
                draftActionTypeOverride = request.actionTypeOverride
                draftActionTypeOverridePrompt = request.displayText
                composerFocused = request.shouldFocusComposer
            }
            return
        }
        guard let activity = completedActivities.first(where: { $0.hkUUID == activityUUID }) else {
            chatStore.presentError(language.reviewRunNotFoundError)
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
            draft = messages(in: existingThread.uuid).isEmpty ? request.displayText : ""
        } else {
            threadID = createNewThread(title: reviewThreadTitle(for: activity), reviewActivityUUID: activity.hkUUID)
            draft = request.displayText
        }
        draftActionTypeOverride = request.actionTypeOverride
        draftActionTypeOverridePrompt = request.displayText
        evidence = EvidenceSelection(readinessSnapshot: true, weekPlan: true, workout: .completed(activity.hkUUID), hasPhoto: false)
        chatSession.activeThreadID = threadID
        composerFocused = request.shouldFocusComposer
        onReviewRequestConsumed(request)
    }

    private func reviewThreadTitle(for activity: CompletedActivity) -> String {
        let distance = Formatters.kilometers(activity.distanceMeters).replacingOccurrences(of: " ", with: "")
        let date = activity.date.formatted(.dateTime.month(.abbreviated).day().locale(language.uiLocale))
        return language.reviewRunThreadTitle(distance: distance, date: date)
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
    private func createNewThread(title: String? = nil, reviewActivityUUID: UUID? = nil) -> UUID {
        let thread = ChatThread(title: title ?? language.newChatFallbackTitle, reviewActivityUUID: reviewActivityUUID)
        modelContext.insert(thread)
        chatSession.activeThreadID = thread.uuid
        draft = ""
        draftActionTypeOverride = nil
        draftActionTypeOverridePrompt = nil
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
            title: language.previousChatTitle,
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
            return isSoftwareKeyboardVisible ? language.composerTypingPlaceholder : language.askCoachChangeWorkoutPlaceholder
        }
        return isSoftwareKeyboardVisible ? language.composerTypingPlaceholder : language.askCoachAnythingPlaceholder
    }

    private var contextualSuggestionLabel: String {
        contextualWorkout?.status == .done || contextualActivity != nil ? language.reviewWorkoutStripLabel : language.editWorkoutStripLabel
    }

    private var contextualSuggestionPrompts: [String] {
        if contextualActivity != nil {
            return [
                language.reviewRunAgainstTargetPrompt,
                language.adjustNextAfterRunPrompt
            ]
        }
        guard let workout = contextualWorkout else { return [] }
        if workout.status == .done {
            return [
                language.reviewCompletedWorkoutPrompt,
                language.adjustNextAfterRunPrompt
            ]
        }
        if workout.isScheduleLocked || workout.kind == .race {
            return [
                language.reviewWhyFixedPrompt,
                language.askSafeAlternativesPrompt
            ]
        }
        return [
            language.changeDistanceOrDurationPrompt,
            language.moveThisWorkoutPrompt
        ]
    }

    private var contextualEyebrow: String {
        if contextualActivity != nil { return language.reviewWithCoachStatus }
        if contextualWorkout?.status == .done || contextualWorkout?.isScheduleLocked == true || contextualWorkout?.kind == .race { return language.reviewWithCoachStatus }
        return language.editingWorkoutStatus
    }

    private var contextualTitle: String {
        if let workout = contextualWorkout { return workout.kind?.displayName ?? "Run" }
        if contextualActivity != nil {
            return language.completedRunTitle
        }
        return language.workoutUnavailableTitle
    }

    private var contextualDateText: String {
        if let workout = contextualWorkout {
            return workout.date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(language.uiLocale))
        }
        if let activity = contextualActivity {
            return activity.date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(language.uiLocale))
        }
        return language.backToCalendarLabel
    }

    private var contextualSymbolName: String {
        contextualWorkout?.kind?.symbolName ?? "figure.run"
    }

    private var contextualMetricPairs: [(String, String)] {
        if let workout = contextualWorkout {
            var pairs = [(language.distanceLabel, Formatters.kilometers(workout.distanceKm * 1000))]
            if let duration = workout.expectedDurationSeconds {
                pairs.append((language.durationLabel, Formatters.duration(duration)))
            }
            if let pace = workout.paceBand {
                pairs.append((language.paceLabel, Formatters.paceBand(pace)))
            }
            return pairs
        }
        if let activity = contextualActivity {
            return [
                (language.distanceLabel, Formatters.kilometers(activity.distanceMeters)),
                (language.durationLabel, Formatters.duration(activity.durationSeconds)),
                (language.paceLabel, Formatters.pace(activity.avgPaceSecondsPerKm))
            ]
        }
        return [(language.statusLabel, language.unavailableLabel)]
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
        .accessibilityLabel(language.workoutContextLabel(title: contextualTitle, date: contextualDateText))
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

    private func isVisibleConversationMessage(_ message: ChatMessage) -> Bool {
        if isPlanAuditMessage(message) { return false }
        guard message.role == .assistant, message.assistantStatus == .dismissed else { return true }
        return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || message.interaction != nil
            || message.appliedAdjustment != nil
    }
}

private struct ChatScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatBottomAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatScrollState: Equatable {
    var isNearBottom = true
    var isFollowingStream = true
    var isUserDragging = false
    var hasUnseenContent = false
    var lastVisibleMessageId: UUID?
}

private extension Notification.Name {
    static let torChatContinueAnswerRequested = Notification.Name("torChatContinueAnswerRequested")
}

private struct SavedPromptsSheet: View {
    let prompts: [String]
    let language: CoachLanguage
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
                    Text(language.savedQuestionsLabel)
                        .font(.torHeading(20, .bold))
                        .foregroundStyle(Theme.text)
                    Text(language.savedPromptsSubtitle)
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
                .accessibilityLabel(language.closeLabel)
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
                    .accessibilityLabel(language.insertSavedPromptLabel(prompt))
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
    let language: CoachLanguage
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
                        language.noChatsTitle,
                        systemImage: "message",
                        description: Text(language.noChatsDescription)
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
                                    Label(language.archiveLabel, systemImage: "archivebox")
                                }
                                .tint(Theme.bad)
                            }
                            .contextMenu {
                                Button {
                                    togglePin(thread)
                                } label: {
                                    Label(thread.pinnedAt == nil ? language.pinChatLabel : language.unpinChatLabel, systemImage: thread.pinnedAt == nil ? "pin" : "pin.slash")
                                }
                                Button {
                                    beginRename(thread)
                                } label: {
                                    Label(language.renameLabel, systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    archive(thread)
                                } label: {
                                    Label(language.archiveLabel, systemImage: "archivebox")
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(language.chatsNavTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.doneLabel) { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .alert(language.renameChatTitle, isPresented: renameAlertBinding) {
                TextField(language.chatNamePlaceholder, text: $renameDraft)
                Button(language.cancelLabel, role: .cancel) { clearRenameDraft() }
                Button(language.saveLabel) { saveRename() }
            } message: {
                Text(language.renameChatMessage)
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
                                    .accessibilityLabel(language.pinnedLabel)
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
                    Label(thread.pinnedAt == nil ? language.pinChatLabel : language.unpinChatLabel, systemImage: thread.pinnedAt == nil ? "pin" : "pin.slash")
                }
                Button {
                    beginRename(thread)
                } label: {
                    Label(language.renameLabel, systemImage: "pencil")
                }
                Button(role: .destructive) {
                    archive(thread)
                } label: {
                    Label(language.archiveLabel, systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 36, height: 36)
                    .background(Theme.chip, in: Circle())
            }
            .accessibilityLabel(language.chatOptionsLabel)
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
        thread.title = clean.isEmpty ? language.newChatFallbackTitle : clean
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
        return clean.isEmpty ? language.newChatFallbackTitle : clean
    }

    private func relativeDate(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = language.uiLocale
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
    var actionTypeOverride: CoachRequestActionType? = nil
    var expectedResponseInteraction: CoachResponseInteraction? = nil
    var displayText: String? = nil
    var contextSnapshotId: String? = nil
    var contextItems: [CoachContextItem] = []
    var focusComposerAfterSend = false
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
    let language: CoachLanguage
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
                    Label(language.planCardUpdatedTitle, systemImage: "checkmark.circle.fill")
                        .font(.torHeading(15, .bold))
                        .foregroundStyle(Theme.good)
                    Text(summary.replacingOccurrences(of: "Applied: ", with: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    if let date {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(language.uiLocale)))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.dim)
                    }
                    HStack(spacing: 8) {
                        transactionButton(language.viewInCalendarLabel, systemImage: "calendar", prominent: true, action: onViewCalendar)
                        if undo == .safe {
                            transactionButton(language.undoLabel, systemImage: "arrow.uturn.backward", prominent: false, action: onUndo)
                        }
                    }
                case .failure(let userMessage, let technicalDetails, _):
                    Label(failureTitle(for: technicalDetails), systemImage: "exclamationmark.triangle.fill")
                        .font(.torHeading(15, .bold))
                        .foregroundStyle(Theme.bad)
                    Text(userMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        transactionButton(language.retryLabel, systemImage: "arrow.clockwise", prominent: true, action: onRetry)
                        transactionButton(language.keepOldPlanLabel, systemImage: "xmark", prominent: false, action: onDismiss)
                    }
                    DisclosureGroup(language.viewTechnicalDetailsLabel, isExpanded: $showsTechnicalDetails) {
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

    private func failureTitle(for technical: String) -> String {
        let lower = technical.lowercased()
        if lower.contains("missing") || lower.contains("couldn't be read") || lower.contains("duration") || lower.contains("pace") { return language.planFailureCantCreate }
        if lower.contains("load") || lower.contains("volume") || lower.contains("ramp") || lower.contains("safe") { return language.planFailureNotSuitable }
        return language.planFailureGeneric
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
    let language: CoachLanguage
    let requiresConfirmation: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(language.dataSourcesUsedTitle)
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
                            Label(language.useEvidenceAndSendLabel, systemImage: "paperplane.fill")
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
                        Button(language.cancelLabel, action: onCancel)
                    }
                }
                if !requiresConfirmation {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.doneLabel, action: onConfirm)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }
}
