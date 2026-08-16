import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ChatView: View {
    private let bottomNavigation: AnyView?

    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.date) private var allMessages: [ChatMessage]
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var chatThreads: [ChatThread]
    @Query(sort: \PlannedWorkout.date) private var plannedWorkouts: [PlannedWorkout]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readinessDays: [DailyReadiness]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var completedActivities: [CompletedActivity]
    @EnvironmentObject private var chatStore: CoachChatStore
    @EnvironmentObject private var replacementCoordinator: WorkoutReplacementCoordinator
    @State private var draft = ""
    @State private var hasAPIKey = false
    @State private var evidence = EvidenceSelection()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageAttachment: CoachImageAttachment?
    @State private var selectedImage: UIImage?
    @State private var evidenceReview: EvidenceReviewPresentation?
    @State private var isChatListPresented = false
    @State private var activeThreadID: UUID?
    @AppStorage("coachEvidenceReviewed") private var coachEvidenceReviewed = false
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private let calendar = Calendar.current
    private let bottomAnchorID = "chat-feed-bottom-anchor"

    init(bottomNavigation: AnyView? = nil) {
        self.bottomNavigation = bottomNavigation
    }

    private var language: CoachLanguage {
        CoachLanguage(rawValue: languageRaw) ?? .en
    }

    private var messages: [ChatMessage] {
        guard let activeThreadID else { return [] }
        return allMessages.filter { $0.threadID == activeThreadID }
    }

    private var activeThread: ChatThread? {
        guard let activeThreadID else { return nil }
        return chatThreads.first { $0.uuid == activeThreadID }
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
            chatStore.lastError = nil
            migrateLegacyMessagesIfNeeded()
            removePersistedTransientErrorMessages()
            createNewThreadForOpeningIfNeeded()
        }
        .onAppear {
            refreshKeyState()
            chatStore.lastError = nil
            migrateLegacyMessagesIfNeeded()
            removePersistedTransientErrorMessages()
            createNewThreadForOpeningIfNeeded()
        }
        .onChange(of: allMessages.count) {
            attachUnthreadedMessagesToActiveThread()
        }
        .overlay(alignment: .top) {
            if let error = chatStore.lastError ?? replacementCoordinator.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Theme.bad, in: Capsule())
                .padding(.top, 4)
            }
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
            ChatHistorySheet(threads: chatThreads, activeThreadID: activeThreadID) { threadID in
                activeThreadID = threadID
                isChatListPresented = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var chatBackground: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                colors: [
                    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x07070C) : UIColor(hex: 0xFFFFFF) }),
                    Theme.bg,
                    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x10111A) : UIColor(hex: 0xEEF1F8) })
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Theme.accent.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            RadialGradient(
                colors: [Theme.good.opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
        }
    }

    private var topControlDeck: some View {
        HStack(alignment: .top) {
            LiquidGlassGroup {
                Button { isChatListPresented = true } label: {
                    Image(systemName: "line.3.horizontal").torTopControlIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Menu")

                Button { createNewThread() } label: {
                    Image(systemName: "square.and.pencil").torTopControlIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New conversation")
            }

            Spacer()

            LiquidGlassGroup {
                Button {} label: {
                    Image(systemName: "bell").torTopControlIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")

                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape").torTopControlIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
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
                readinessGlassCard
                    .padding(.top, 54)
                suggestedPromptRows
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readinessGlassCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.good.opacity(0.16))
                    Circle().strokeBorder(Theme.good.opacity(0.28), lineWidth: 1)
                    Circle().fill(Theme.good).frame(width: 9, height: 9)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Hôm nay: Sẵn sàng tập luyện")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Phục hồi tốt · Chưa có dấu hiệu quá tải")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Theme.border)

            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.good)
                    .frame(width: 24, height: 24)
                    .background(Theme.good.opacity(0.12), in: Circle())
                Text("Bài dự kiến: Tempo 8 km")
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
            ChatPromptButton("Analyze my last activity", systemImage: "waveform.path.ecg") {
                draft = "Analyze my last activity"
            }
            ChatPromptButton("How is my training load this week?", systemImage: "chart.line.uptrend.xyaxis") {
                draft = "How is my training load this week?"
            }
            ChatPromptButton("What should I do today?", systemImage: "sun.max") {
                draft = "What should I do today?"
            }
        }
    }

    private var messageFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.date)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: chatStore.isSending) {
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: activeThreadID) {
                scrollToBottom(proxy, animated: false)
            }
        }
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

    private var missingKeyView: some View {
        ContentUnavailableView {
            Label("API Key Needed", systemImage: "key")
        } description: {
            Text("Add your Anthropic API key before chatting.")
        } actions: {
            NavigationLink("Open Settings") {
                SettingsView()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var chatFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !messages.isEmpty || selectedImageAttachment != nil || evidence.workout != nil || evidence.hasPhoto {
                ChatContextTrayView(
                    evidence: $evidence,
                    selectedPhotoItem: $selectedPhotoItem,
                    selectedImageAttachment: $selectedImageAttachment,
                    selectedImage: $selectedImage,
                    plannedWorkouts: plannedWorkouts,
                    completedActivities: completedActivities,
                    onReviewEvidence: { presentEvidenceReview(confirming: nil) }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            // A staged swap takes over the suggestion slot: it needs a decision
            // before anything else can be asked.
            if let pending = replacementCoordinator.pending, !replacementCoordinator.isConfirming {
                PlanUpdateCard(
                    pending: pending,
                    language: language,
                    onApply: { replacementCoordinator.confirm(pending.id) },
                    onKeep: { replacementCoordinator.cancel() },
                    // Asking why is not a decision to swap, and the composer is
                    // locked while a proposal stands — so dismiss it and prefill
                    // the question. Nothing is applied either way.
                    onAskWhy: {
                        replacementCoordinator.cancel()
                        draft = language.whySwapPrompt
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if !messages.isEmpty, !chatStore.isSending {
                CoachAskNextStrip(prompts: suggestionPrompts, label: language.askNextLabel) { draft = $0 }
            }
            composer
            if let bottomNavigation {
                bottomNavigation
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, bottomNavigation.map { _ in 4 } ?? 8)
        .background(.clear)
        .animation(.easeOut(duration: 0.2), value: replacementCoordinator.pending)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button("Use readiness snapshot") { evidence.readinessSnapshot = true }
                Button("Review evidence") { presentEvidenceReview(confirming: nil) }
                if selectedImageAttachment != nil {
                    Button("Clear image", role: .destructive) { clearImageAttachment() }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            TextField("Ask anything", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .lineLimit(1...5)
                .padding(.vertical, 12)
                .disabled(replacementCoordinator.pending != nil || replacementCoordinator.isConfirming)

            Button { draft = "What should I do today?" } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)

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
            .disabled(isSendDisabled)
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .torGlass(cornerRadius: 28, tint: .graphite)
    }

    private var isSendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || chatStore.isSending
            || replacementCoordinator.pending != nil
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
        let pending = PendingCoachSend(text: text, attachments: attachments, evidence: evidence)
        guard coachEvidenceReviewed else {
            presentEvidenceReview(confirming: pending)
            return
        }
        performSend(pending)
    }

    private func performSend(_ pending: PendingCoachSend) {
        let reviewedSnapshot = pending.reviewedSnapshot
        let threadID = activeThreadID ?? createNewThread()
        draft = ""
        Task {
            await chatStore.send(
                text: pending.text,
                model: model,
                attachments: pending.attachments,
                evidence: pending.evidence,
                groundingSnapshot: reviewedSnapshot,
                threadID: threadID,
                in: modelContext
            )
            evidence.workout = nil
            clearImageAttachment()
        }
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
                    reviewedSnapshot: snapshot
                )
            }
            evidenceReview = EvidenceReviewPresentation(snapshot: snapshot, pendingSend: pendingWithSnapshot)
        } catch {
            chatStore.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    private func createNewThread() -> UUID {
        let thread = ChatThread()
        modelContext.insert(thread)
        activeThreadID = thread.uuid
        draft = ""
        evidence.workout = nil
        clearImageAttachment()
        try? modelContext.save()
        return thread.uuid
    }

    private func createNewThreadForOpeningIfNeeded() {
        if let activeThreadID,
           allMessages.contains(where: { $0.threadID == activeThreadID }) == false {
            return
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
        guard let activeThreadID else { return }
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

    private var currentAttachments: [CoachContextAttachment] {
        var attachments: [CoachContextAttachment] = []
        if evidence.readinessSnapshot {
            attachments.append(.health)
        }
        switch evidence.workout {
        case .planned(let uuid):
            attachments.append(.plannedWorkout(uuid))
        case .completed(let uuid):
            attachments.append(.completedActivity(uuid))
        case nil:
            break
        }
        if let selectedImageAttachment {
            attachments.append(.image(selectedImageAttachment))
        }
        return attachments
    }

    private func clearImageAttachment() {
        selectedPhotoItem = nil
        selectedImageAttachment = nil
        selectedImage = nil
        evidence.hasPhoto = false
    }
}

private struct ChatHistorySheet: View {
    let threads: [ChatThread]
    let activeThreadID: UUID?
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if threads.isEmpty {
                        ContentUnavailableView(
                            "No chats yet",
                            systemImage: "message",
                            description: Text("Your coach conversations will show up here.")
                        )
                        .foregroundStyle(Theme.text, Theme.dim)
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(threads) { thread in
                            chatRow(thread)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .presentationBackground(Theme.bg)
        .presentationDragIndicator(.visible)
    }

    private func chatRow(_ thread: ChatThread) -> some View {
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
                    Text(title(for: thread))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
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
}

private struct EvidenceReviewPresentation: Identifiable {
    let id = UUID()
    let snapshot: GroundingSnapshot
    let pendingSend: PendingCoachSend?
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
                        Text("Evidence Review")
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
                            Label("Use Evidence and Send", systemImage: "paperplane.fill")
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
                        Button("Cancel", action: onCancel)
                    }
                }
                if !requiresConfirmation {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onConfirm)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }
}
