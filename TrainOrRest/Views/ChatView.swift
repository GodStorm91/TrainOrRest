import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ChatView: View {
    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.date) private var messages: [ChatMessage]
    @Query(sort: \PlannedWorkout.date) private var plannedWorkouts: [PlannedWorkout]
    @Query(sort: \CompletedActivity.date, order: .reverse) private var completedActivities: [CompletedActivity]
    @StateObject private var chatStore = CoachChatStore()
    @State private var draft = ""
    @State private var hasAPIKey = false
    @State private var includeHealthContext = true
    @State private var selectedWorkoutContext: WorkoutContextSelection?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageAttachment: CoachImageAttachment?
    @State private var selectedImage: UIImage?
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private let calendar = Calendar.current

    private var language: CoachLanguage {
        CoachLanguage(rawValue: languageRaw) ?? .en
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasAPIKey {
                missingKeyView
            } else if messages.isEmpty {
                emptyState
            } else {
                messageFeed
                    .background(Theme.bg)
            }
            if hasAPIKey {
                chatFooter
            }
        }
        .background(Theme.bg)
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { coachHeader }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .task { refreshKeyState() }
        .onAppear { refreshKeyState() }
        .overlay(alignment: .top) {
            if let error = chatStore.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Theme.bad, in: Capsule())
                    .padding(.top, 4)
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
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.good)
                        .frame(width: 6, height: 6)
                    Text(language.coachStatus)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
            }
            Text(language.flag)
                .font(.system(size: 15))
                .accessibilityLabel(language.englishName)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Ask Your Coach",
                systemImage: "message.badge.waveform",
                description: Text("Ask about today's run, paste a table, attach health context, or request a checked plan adjustment.")
            )
            VStack(alignment: .leading, spacing: 8) {
                ChatPromptButton("Why is today's workout right for me?") { draft = "Why is today's workout right for me?" }
                ChatPromptButton("Compare my readiness and recent training load.") {
                    draft = "Compare my readiness and recent training load."
                }
                ChatPromptButton("Turn this screenshot into practical training advice.") {
                    draft = "Turn this screenshot into practical training advice."
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var messageFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.date)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) {
                guard let last = messages.last?.date else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
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
            ChatContextTrayView(
                includeHealthContext: $includeHealthContext,
                selectedWorkoutContext: $selectedWorkoutContext,
                selectedPhotoItem: $selectedPhotoItem,
                selectedImageAttachment: $selectedImageAttachment,
                selectedImage: $selectedImage,
                plannedWorkouts: plannedWorkouts,
                completedActivities: completedActivities
            )
            if !messages.isEmpty, !chatStore.isSending {
                CoachAskNextStrip(prompts: suggestionPrompts, label: language.askNextLabel) { draft = $0 }
            }
            composer
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField(language.composerPlaceholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            Button {
                send()
            } label: {
                Group {
                    if chatStore.isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.accentSoft, radius: 8, y: 3)
                .opacity(isSendDisabled ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isSendDisabled)
        }
    }

    private var isSendDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatStore.isSending
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
        draft = ""
        Task {
            await chatStore.send(text: text, model: model, attachments: attachments, in: modelContext)
            selectedWorkoutContext = nil
            clearImageAttachment()
        }
    }

    private func refreshKeyState() {
        hasAPIKey = !((try? KeychainStore.load()) ?? "").isEmpty
    }

    private var currentAttachments: [CoachContextAttachment] {
        var attachments: [CoachContextAttachment] = []
        if includeHealthContext {
            attachments.append(.health)
        }
        switch selectedWorkoutContext {
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
    }
}
