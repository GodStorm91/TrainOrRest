import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(PersonalCoachSettings.weightKgKey) private var weightKg = ""
    @AppStorage(WorkoutPushSettings.enabledKey) private var watchPushEnabled = false
    @AppStorage(WorkoutPushSettings.athleteIDKey) private var athleteID = ""

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var pushService: WorkoutPushService
    @EnvironmentObject private var googleCalendar: GoogleCalendarSyncService
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CoachMemoryItem.updatedAt, order: .reverse) private var memoryItems: [CoachMemoryItem]
    @State private var intervalsAPIKey = ""

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        Form {
            Section("Account") {
                NavigationLink {
                    AthleteProfileEditView()
                } label: {
                    settingsRow("Personal information", systemImage: "person", value: athleteSummary)
                }
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    settingsRow("Language", systemImage: "globe", value: language.nativeName)
                }
            }

            Section("Appearance") {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    settingsRow("Appearance", systemImage: "circle.lefthalf.filled", value: appearance.title)
                }
                .accessibilityLabel("Change appearance")
            }

            Section("Connected Services") {
                settingsRow("Apple Health", systemImage: "heart", value: "Connected")
                settingsRow("Garmin", systemImage: "figure.run", value: "via Apple Health")
                NavigationLink {
                    CalendarsSettingsView()
                } label: {
                    settingsRow("Calendars", systemImage: "calendar.badge.clock", value: googleCalendarSummary)
                }
                .accessibilityLabel("Manage calendar connections")
                NavigationLink {
                    IntervalsConnectionSettingsView()
                } label: {
                    settingsRow("intervals.icu", systemImage: "point.3.connected.trianglepath.dotted", value: intervalsStatusSummary)
                }
                .accessibilityLabel("Manage intervals.icu connection")
            }

            Section("Watch Delivery") {
                NavigationLink {
                    WatchDeliverySettingsView()
                } label: {
                    settingsRow("Watch Push", systemImage: "applewatch.radiowaves.left.and.right", value: watchPushSummary)
                }
            }

            Section("Coach & Personalization") {
                NavigationLink {
                    CoachMemorySettingsView()
                } label: {
                    settingsRow("Coach Memory", systemImage: "brain.head.profile", value: memorySummary)
                }
                NavigationLink {
                    CoachProviderSettingsView()
                } label: {
                    settingsRow("Coach provider", systemImage: "sparkles", value: "Model & API")
                }
            }

            Section("Data & Privacy") {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    settingsRow("Health-data permissions", systemImage: "lock.shield", value: "iOS Settings")
                }
                settingsRow("Data storage", systemImage: "externaldrive", value: "On this device")
            }

            Section("Support") {
                settingsRow("About RestOrTrain", systemImage: "info.circle", value: Bundle.main.appVersionSummary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Done") { dismiss() }
        }
        .task {
            try? PersonalCoachSettings.migrateLegacyCoachMemoryIfNeeded(in: modelContext)
            intervalsAPIKey = (try? KeychainStore.load(account: KeychainStore.intervalsICUAccount)) ?? ""
        }
    }

    private func settingsRow(_ title: String, systemImage: String, value: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(title)
            Spacer()
            if let value, !value.isEmpty {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: 44)
    }

    private var athleteSummary: String {
        if let weight = clean(weightKg) { return "\(weight) kg" }
        return "Not complete"
    }

    private var intervalsStatusSummary: String {
        let hasAthlete = !athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasKey = !intervalsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasAthlete && hasKey ? "Connected" : "Not connected"
    }

    private var watchPushSummary: String {
        if !watchPushEnabled { return "Off" }
        if let last = pushService.lastPushAt { return last.formatted(date: .abbreviated, time: .shortened) }
        return "On"
    }

    private var googleCalendarSummary: String {
        let connection = googleCalendar.connection()
        switch connection.connectionStatus {
        case .connected: return "Google connected"
        case .syncing, .initialSync: return "Syncing"
        case .needsReconnect, .calendarMissing, .partialFailure: return "Needs attention"
        case .offlineQueued: return "Queued"
        default: return "Not connected"
        }
    }

    private var memorySummary: String {
        let count = memoryItems.count
        if count == 0 { return "Empty" }
        return count == 1 ? "1 memory" : "\(count) memories"
    }

    private func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CalendarsSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    GoogleCalendarSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        Text("Google Calendar")
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
            } footer: {
                Text("Calendar integrations mirror RestOrTrain workouts outward. RestOrTrain stays the source of truth.")
            }
        }
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppearanceSettingsView: View {
    var body: some View {
        Form {
            Section {
                AppAppearanceSelector(compact: true)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            } footer: {
                Text("Use System follows this iPhone. Light and Dark override it immediately without restarting or resetting where you are.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LanguageSettingsView: View {
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    var body: some View {
        Form {
            Section {
                ForEach(CoachLanguage.allCases) { language in
                    Button {
                        languageRaw = language.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Text(language.flag).font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(language.nativeName)
                                    .foregroundStyle(.primary)
                                Text(language.englishName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if language.rawValue == languageRaw {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Coach chat and suggestions use this language.")
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IntervalsConnectionSettingsView: View {
    @AppStorage(WorkoutPushSettings.athleteIDKey) private var athleteID = ""
    @AppStorage(WorkoutPushSettings.enabledKey) private var watchPushEnabled = false
    @EnvironmentObject private var pushService: WorkoutPushService
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var status: String?
    @State private var isSyncing = false

    private var isConnected: Bool {
        !athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                connectionSummary
            }

            Section {
                TextField("Athlete ID", text: $athleteID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    if showAPIKey {
                        TextField("API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("API key", text: $apiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                    }
                    Button(showAPIKey ? "Hide" : "Reveal") { showAPIKey.toggle() }
                        .font(.caption.weight(.semibold))
                }
                Button {
                    saveConnection()
                } label: {
                    Label("Save connection", systemImage: "checkmark.shield")
                }
                .disabled(!canSave)
                .accessibilityLabel("Save intervals.icu connection")
            } header: {
                Text("Manage connection")
            } footer: {
                Text("On the web: intervals.icu Settings, Developer Settings. Generate an API key and copy the Athlete ID from that page. Then Settings, Connections, Garmin, Upload planned workouts. Without that tick the watch stays empty.")
            }

            Section {
                Toggle("Watch Push", isOn: $watchPushEnabled)
                    .frame(minHeight: 44)
            } footer: {
                Text("Watch Push sends planned workouts through intervals.icu after the connection is saved.")
            }

            if let status {
                Section {
                    Text(status)
                        .foregroundStyle(status.hasPrefix("Could not") ? Theme.bad : Theme.good)
                }
            }

            if let report = pushService.lastDebugReport, !report.isEmpty {
                Section {
                    DebugReportView(text: report)
                } header: {
                    Text("Garmin delivery debug")
                } footer: {
                    Text("This is the exact intervals.icu push path. If the DSL contains pace but Garmin still shows distance only, the failure is in intervals.icu to Garmin export or Garmin Connect parsing.")
                }
            }
        }
        .navigationTitle("intervals.icu")
        .navigationBarTitleDisplayMode(.inline)
        .task { apiKey = (try? KeychainStore.load(account: KeychainStore.intervalsICUAccount)) ?? "" }
    }

    private var connectionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "link.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isConnected ? Theme.good : Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isConnected ? "Connected" : "Connect intervals.icu")
                        .font(.headline)
                    Text(isConnected ? lastSyncText : "Sync your training plan and deliver workouts to supported devices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if isConnected {
                Button {
                    syncNow()
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var lastSyncText: String {
        if pushService.lastPushError != nil { return "Last sync failed" }
        if let last = pushService.lastPushAt { return "Last sync \(last.formatted(date: .abbreviated, time: .shortened))" }
        return "Ready to sync"
    }

    private var canSave: Bool {
        !athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveConnection() {
        do {
            try KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: KeychainStore.intervalsICUAccount)
            status = "Connection saved."
        } catch {
            status = "Could not save intervals.icu key."
        }
    }

    private func syncNow() {
        isSyncing = true
        Task {
            await pushService.reconcile(requireEnabled: false, forceRecreate: true)
            await MainActor.run {
                isSyncing = false
                if let skip = pushService.lastPushSkipReason {
                    status = "Sync skipped. \(skip)"
                } else {
                    status = pushService.lastPushError == nil ? "Sync complete. Existing Garmin workouts were recreated." : "Could not sync intervals.icu."
                }
            }
        }
    }
}

struct WatchDeliverySettingsView: View {
    @AppStorage(WorkoutPushSettings.enabledKey) private var watchPushEnabled = false
    @EnvironmentObject private var pushService: WorkoutPushService
    @State private var isSyncing = false

    var body: some View {
        Form {
            Section {
                Toggle("Watch Push", isOn: $watchPushEnabled)
                    .frame(minHeight: 44)
                if let last = pushService.lastPushAt {
                    LabeledContent("Last synchronization", value: last.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Last synchronization", value: "Never")
                }
                if let error = pushService.lastPushError {
                    Text("Last sync failed: \(error)")
                        .font(.caption)
                        .foregroundStyle(Theme.bad)
                }
                Button {
                    syncNow()
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing || !watchPushEnabled)
            } footer: {
                Text("Watch Push sends planned workouts through intervals.icu. Manage the intervals.icu connection separately under Connected Services.")
            }

            if let report = pushService.lastDebugReport, !report.isEmpty {
                Section {
                    DebugReportView(text: report)
                } header: {
                    Text("Garmin delivery debug")
                }
            }
        }
        .navigationTitle("Watch Delivery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncNow() {
        isSyncing = true
        Task {
            await pushService.reconcile(forceRecreate: true)
            await MainActor.run { isSyncing = false }
        }
    }
}

struct DebugReportView: View {
    var text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(text)
    }
}

struct CoachMemorySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @Query(sort: \CoachMemoryItem.updatedAt, order: .reverse) private var memoryItems: [CoachMemoryItem]
    @State private var deleteCandidate: CoachMemoryItem?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingClearConfirmation = false
    @State private var errorMessage: String?

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    private var sortedMemories: [CoachMemoryItem] {
        memoryItems.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.uuid.uuidString < rhs.uuid.uuidString
        }
    }

    var body: some View {
        Form {
            Section {
                Text(language.coachMemoryIntro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if sortedMemories.isEmpty {
                    CoachMemoryEmptyState(language: language)
                } else {
                    ForEach(sortedMemories, id: \.uuid) { item in
                        CoachMemoryCard(
                            item: item,
                            dateText: dateText(for: item.updatedAt),
                            language: language,
                            onDelete: {
                                deleteCandidate = item
                                isShowingDeleteConfirmation = true
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                NavigationLink {
                    CoachMemoryEditorView()
                } label: {
                    Label(language.addMemoryTitle, systemImage: "plus")
                }
                .accessibilityLabel(language.addCoachMemoryAccessibilityLabel)
            } header: {
                Text(language.rememberedAthleteContextTitle)
            } footer: {
                Text(language.coachMemoryFooter)
            }

            Section {
                Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Label(language.clearAllCoachMemoryTitle, systemImage: "trash")
                }
                .disabled(sortedMemories.isEmpty)
                .accessibilityLabel(language.clearAllCoachMemoryAccessibilityLabel)
            }
        }
        .navigationTitle(language.coachMemoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CoachMemoryEditorView()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(language.addCoachMemoryAccessibilityLabel)
            }
        }
        .task {
            do {
                try PersonalCoachSettings.migrateLegacyCoachMemoryIfNeeded(in: modelContext)
            } catch {
                errorMessage = language.loadMemoryErrorTitle
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: true)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: false)
        }
        .alert(language.deleteMemoryConfirmationTitle, isPresented: $isShowingDeleteConfirmation) {
            Button(language.cancelTitle, role: .cancel) { deleteCandidate = nil }
            Button(language.deleteTitle, role: .destructive) { deleteSelectedMemory() }
        } message: {
            Text(language.deleteMemoryConfirmationMessage)
        }
        .alert(language.clearAllConfirmationTitle, isPresented: $isShowingClearConfirmation) {
            Button(language.cancelTitle, role: .cancel) {}
            Button(language.clearAllConfirmationAction, role: .destructive) { clearAllMemories() }
        } message: {
            Text(language.clearAllConfirmationMessage)
        }
        .alert(language.errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(language.tryAgainTitle) {
                errorMessage = nil
                try? PersonalCoachSettings.migrateLegacyCoachMemoryIfNeeded(in: modelContext)
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deleteSelectedMemory() {
        guard let deleteCandidate else { return }
        do {
            try PersonalCoachSettings.deleteCoachMemory(deleteCandidate, in: modelContext)
        } catch {
            errorMessage = language.deleteMemoryErrorMessage
        }
        self.deleteCandidate = nil
    }

    private func clearAllMemories() {
        do {
            try PersonalCoachSettings.clearCoachMemory(in: modelContext)
        } catch {
            errorMessage = language.loadMemoryErrorTitle
        }
    }

    private func dateText(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

struct CoachProviderSettingsView: View {
    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @StateObject private var chatStore = CoachChatStore()
    @State private var anthropicAPIKey = ""
    @State private var openAIAPIKey = ""
    @State private var status: String?
    @State private var isTesting = false

    private let anthropicModels = [
        CoachChatConfig.defaultModel,
        "claude-haiku-4-5",
        "claude-opus-4-8"
    ]
    private let openAIModels = [
        CoachChatConfig.defaultOpenAIModel,
        "gpt-4o-mini",
        "gpt-4.1-mini"
    ]

    var body: some View {
        Form {
            Section("Coach provider") {
                Picker("Model", selection: $model) {
                    Section("OpenAI") {
                        ForEach(openAIModels, id: \.self) { Text(modelLabel($0)).tag($0) }
                    }
                    Section("Claude") {
                        ForEach(anthropicModels, id: \.self) { Text(modelLabel($0)).tag($0) }
                    }
                }
            }
            Section("OpenAI API") {
                SecureField("OpenAI API key", text: $openAIAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button {
                    saveAndTestOpenAI()
                } label: {
                    if isTesting {
                        ProgressView()
                    } else {
                        Label("Save OpenAI and Test", systemImage: "checkmark.shield")
                    }
                }
                .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
            }
            Section("Claude API") {
                SecureField("Anthropic API key", text: $anthropicAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button {
                    saveAndTestAnthropic()
                } label: {
                    Label("Save Claude and Test", systemImage: "checkmark.shield")
                }
                .disabled(anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
            }
            if let status {
                Section {
                    Text(status)
                        .foregroundStyle(status == "Connection OK" ? .green : .secondary)
                }
            }
        }
        .navigationTitle("Coach Provider")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            anthropicAPIKey = (try? KeychainStore.load()) ?? ""
            openAIAPIKey = (try? KeychainStore.load(account: KeychainStore.openAIAPIKeyAccount)) ?? ""
        }
    }

    private func saveAndTestOpenAI() {
        isTesting = true
        let trimmed = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !CoachModelProvider.isOpenAIModel(model) { model = CoachChatConfig.defaultOpenAIModel }
        Task {
            do {
                try KeychainStore.save(trimmed, account: KeychainStore.openAIAPIKeyAccount)
                status = await chatStore.testConnection(apiKey: trimmed, model: model)
            } catch {
                status = "Could not save OpenAI API key."
            }
            isTesting = false
        }
    }

    private func saveAndTestAnthropic() {
        isTesting = true
        let trimmed = anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if CoachModelProvider.isOpenAIModel(model) { model = CoachChatConfig.defaultModel }
        Task {
            do {
                try KeychainStore.save(trimmed)
                status = await chatStore.testConnection(apiKey: trimmed, model: model)
            } catch {
                status = "Could not save Anthropic API key."
            }
            isTesting = false
        }
    }

    private func modelLabel(_ id: String) -> String {
        switch id {
        case CoachChatConfig.defaultOpenAIModel:
            "Budget coach (GPT-5 Nano)"
        case "gpt-4o-mini":
            "Cheap balanced coach (GPT-4o mini)"
        case "gpt-4.1-mini":
            "Better OpenAI coach (GPT-4.1 mini)"
        case CoachChatConfig.defaultModel:
            "Balanced Claude coach"
        case "claude-haiku-4-5":
            "Fast Claude coach"
        case "claude-opus-4-8":
            "Deep Claude review"
        default:
            id
        }
    }
}

private struct CoachMemoryCard: View {
    let item: CoachMemoryItem
    let dateText: String
    let language: CoachLanguage
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(dateText)
                        if item.source == .chat {
                            Text(language.learnedFromChatLabel)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    NavigationLink {
                        CoachMemoryEditorView(item: item)
                    } label: {
                        Label(language.editMemoryTitle, systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(language.deleteTitle, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(language.moreActionsForMemoryAccessibilityLabel)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.text), \(dateText)")
    }
}

private struct CoachMemoryEmptyState: View {
    let language: CoachLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(language.noCoachMemoriesTitle, systemImage: "brain.head.profile")
                .font(.headline)
            Text(language.noCoachMemoriesMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                CoachMemoryEditorView()
            } label: {
                Label(language.addMemoryTitle, systemImage: "plus")
            }
            .accessibilityLabel(language.addCoachMemoryAccessibilityLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct CoachMemoryEditorView: View {
    let item: CoachMemoryItem?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @State private var draft: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var pendingExample: String?
    @State private var isShowingReplaceConfirmation = false
    @State private var isShowingDiscardConfirmation = false
    @FocusState private var isEditorFocused: Bool

    init(item: CoachMemoryItem? = nil) {
        self.item = item
        _draft = State(initialValue: item?.text ?? "")
    }

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    private var trimmedDraft: String { PersonalCoachSettings.sanitizedMemoryText(draft) }
    private var isEditing: Bool { item != nil }
    private var hasMeaningfulChange: Bool {
        guard let item else { return !trimmedDraft.isEmpty }
        return PersonalCoachSettings.normalizedMemoryText(item.text) != PersonalCoachSettings.normalizedMemoryText(trimmedDraft)
    }
    private var canSave: Bool {
        !trimmedDraft.isEmpty && hasMeaningfulChange && !isSaving && draft.count <= PersonalCoachSettings.maxMemoryItemCharacters
    }

    var body: some View {
        Form {
            if !isEditorFocused {
                Section {
                    Text(language.memoryEditorIntro)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .frame(minHeight: 170)
                        .focused($isEditorFocused)
                        .autocorrectionDisabled(false)
                        .accessibilityLabel(language.memoryTextFieldAccessibilityLabel)
                    if draft.isEmpty {
                        Text(language.memoryEditorPlaceholder)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                HStack {
                    Spacer()
                    Text("\(draft.count)/\(PersonalCoachSettings.maxMemoryItemCharacters)")
                        .font(.caption)
                        .foregroundStyle(draft.count > PersonalCoachSettings.maxMemoryItemCharacters ? Theme.bad : .secondary)
                }
            }

            Section {
                ForEach(language.coachMemorySuggestedExamples, id: \.self) { example in
                    Button {
                        selectExample(example)
                    } label: {
                        HStack(spacing: 10) {
                            Text(example)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.accent)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(language.suggestedExamplesTitle)
            }

            if let errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage)
                            .foregroundStyle(Theme.bad)
                        Text(language.memoryTextNotLostMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(language.tryAgainTitle) { save() }
                    }
                }
            }
        }
        .navigationTitle(isEditing ? language.editMemoryTitle : language.addMemoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(language.backTitle) { back() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(language.saveTitle)
                    }
                }
                .disabled(!canSave)
                .accessibilityLabel(language.saveMemoryAccessibilityLabel)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(hasMeaningfulChange)
        .task {
            await MainActor.run { isEditorFocused = true }
        }
        .onChange(of: draft) { _, newValue in
            if newValue.count > PersonalCoachSettings.maxMemoryItemCharacters {
                draft = String(newValue.prefix(PersonalCoachSettings.maxMemoryItemCharacters))
            }
        }
        .alert(language.replaceMemoryDraftTitle, isPresented: $isShowingReplaceConfirmation) {
            Button(language.cancelTitle, role: .cancel) { pendingExample = nil }
            Button(language.replaceTitle) {
                if let pendingExample {
                    draft = pendingExample
                }
                pendingExample = nil
            }
        } message: {
            Text(language.replaceMemoryDraftMessage)
        }
        .alert(language.discardChangesTitle, isPresented: $isShowingDiscardConfirmation) {
            Button(language.keepEditingTitle, role: .cancel) {}
            Button(language.discardTitle, role: .destructive) { dismiss() }
        }
    }

    private func selectExample(_ example: String) {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = example
        } else {
            pendingExample = example
            isShowingReplaceConfirmation = true
        }
        isEditorFocused = true
    }

    private func back() {
        if hasMeaningfulChange {
            isShowingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        do {
            if let item {
                try PersonalCoachSettings.updateCoachMemory(item, text: draft, in: modelContext)
            } else {
                _ = try PersonalCoachSettings.addCoachMemory(draft, source: .manual, in: modelContext)
            }
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            errorMessage = language.saveMemoryErrorTitle
        }
    }
}

extension Notification.Name {
    static let torSetBottomDockHidden = Notification.Name("torSetBottomDockHidden")
}

extension CoachLanguage {
    var coachMemoryTitle: String {
        switch self {
        case .en: "Coach Memory"
        case .ja: "コーチメモリー"
        case .vi: "Bộ nhớ Coach"
        }
    }

    var rememberedAthleteContextTitle: String {
        switch self {
        case .en: "Remembered athlete context"
        case .ja: "記憶したアスリート情報"
        case .vi: "Thông tin vận động viên đã ghi nhớ"
        }
    }

    var coachMemoryIntro: String {
        switch self {
        case .en: "RestOrTrain remembers useful facts from your chats. You can also add, edit, or remove memories manually."
        case .ja: "RestOrTrain はチャットから役立つ情報を記憶します。手動で追加、編集、削除もできます。"
        case .vi: "RestOrTrain ghi nhớ các thông tin hữu ích từ cuộc trò chuyện. Anh cũng có thể tự thêm, sửa hoặc xóa ghi nhớ."
        }
    }

    var coachMemoryFooter: String {
        switch self {
        case .en: "Coach uses these facts to personalize future advice. You can edit or remove any item."
        case .ja: "Coach はこれらの情報を使って今後の助言を調整します。各項目は編集または削除できます。"
        case .vi: "Coach dùng các thông tin này để cá nhân hóa lời khuyên sau này. Anh có thể sửa hoặc xóa từng mục."
        }
    }

    var addMemoryTitle: String {
        switch self {
        case .en: "Add memory"
        case .ja: "メモリーを追加"
        case .vi: "Thêm ghi nhớ"
        }
    }

    var editMemoryTitle: String {
        switch self {
        case .en: "Edit Memory"
        case .ja: "メモリーを編集"
        case .vi: "Chỉnh sửa ghi nhớ"
        }
    }

    var deleteTitle: String {
        switch self {
        case .en: "Delete"
        case .ja: "削除"
        case .vi: "Xóa"
        }
    }

    var clearAllCoachMemoryTitle: String {
        switch self {
        case .en: "Clear all coach memory"
        case .ja: "すべてのコーチメモリーを消去"
        case .vi: "Xóa toàn bộ bộ nhớ Coach"
        }
    }

    var saveTitle: String {
        switch self {
        case .en: "Save"
        case .ja: "保存"
        case .vi: "Lưu"
        }
    }

    var backTitle: String {
        switch self {
        case .en: "Back"
        case .ja: "戻る"
        case .vi: "Quay lại"
        }
    }

    var cancelTitle: String {
        switch self {
        case .en: "Cancel"
        case .ja: "キャンセル"
        case .vi: "Hủy"
        }
    }

    var suggestedExamplesTitle: String {
        switch self {
        case .en: "Suggested examples"
        case .ja: "例"
        case .vi: "Gợi ý"
        }
    }

    var noCoachMemoriesTitle: String {
        switch self {
        case .en: "No Coach memories yet"
        case .ja: "Coach のメモリーはまだありません"
        case .vi: "Coach chưa ghi nhớ thông tin nào"
        }
    }

    var noCoachMemoriesMessage: String {
        switch self {
        case .en: "Add useful facts such as your training schedule, injuries, preferences, or race goals. Memory is optional and under your control."
        case .ja: "練習スケジュール、怪我、好み、レース目標など、役立つ安定情報を追加できます。メモリーは任意で、いつでも管理できます。"
        case .vi: "Thêm thông tin hữu ích như lịch tập, chấn thương, sở thích hoặc mục tiêu race. Bộ nhớ là tùy chọn và anh kiểm soát được."
        }
    }

    var memoryEditorIntro: String {
        switch self {
        case .en: "Add a stable fact about your training, body, preferences, schedule, or constraints."
        case .ja: "練習、身体、好み、予定、制約に関する安定した情報を追加します。"
        case .vi: "Thêm một thông tin ổn định về tập luyện, cơ thể, sở thích, lịch trình hoặc ràng buộc của anh."
        }
    }

    var memoryEditorPlaceholder: String {
        switch self {
        case .en: "Write something Coach should remember..."
        case .ja: "Coach に覚えてほしいことを書く..."
        case .vi: "Viết điều Coach nên ghi nhớ..."
        }
    }

    var coachMemorySuggestedExamples: [String] {
        switch self {
        case .en:
            [
                "I can train 8-10 hours per week.",
                "I prefer running in the morning.",
                "My shin hurts when mileage increases quickly.",
                "I am training for a marathon on Oct 25, 2026.",
                "I travel frequently on weekends."
            ]
        case .ja:
            [
                "週に8-10時間トレーニングできます。",
                "朝に走るのが好きです。",
                "走行距離を急に増やすとすねが痛みます。",
                "2026年10月25日のマラソンに向けて練習しています。",
                "週末に移動が多いです。"
            ]
        case .vi:
            [
                "Tôi có thể tập 8-10 giờ mỗi tuần.",
                "Tôi thích chạy vào buổi sáng.",
                "Ống chân của tôi đau khi tăng mileage quá nhanh.",
                "Tôi đang tập cho marathon ngày 25/10/2026.",
                "Tôi thường xuyên đi xa vào cuối tuần."
            ]
        }
    }

    var deleteMemoryConfirmationTitle: String {
        switch self {
        case .en: "Delete this memory?"
        case .ja: "このメモリーを削除しますか？"
        case .vi: "Xóa ghi nhớ này?"
        }
    }

    var deleteMemoryConfirmationMessage: String {
        switch self {
        case .en: "Coach will no longer use this fact in future advice."
        case .ja: "Coach は今後の助言でこの情報を使わなくなります。"
        case .vi: "Coach sẽ không dùng thông tin này cho lời khuyên sau này nữa."
        }
    }

    var clearAllConfirmationTitle: String {
        switch self {
        case .en: "Clear all Coach Memory?"
        case .ja: "すべての Coach メモリーを消去しますか？"
        case .vi: "Xóa toàn bộ bộ nhớ Coach?"
        }
    }

    var clearAllConfirmationMessage: String {
        switch self {
        case .en: "Coach will forget all manually added and chat-learned athlete context. This cannot be undone."
        case .ja: "手動追加およびチャットから学習したアスリート情報をすべて忘れます。元に戻せません。"
        case .vi: "Coach sẽ quên toàn bộ thông tin vận động viên do anh thêm và học từ chat. Không thể hoàn tác."
        }
    }

    var clearAllConfirmationAction: String {
        switch self {
        case .en: "Clear all"
        case .ja: "すべて消去"
        case .vi: "Xóa tất cả"
        }
    }

    var discardChangesTitle: String {
        switch self {
        case .en: "Discard changes?"
        case .ja: "変更を破棄しますか？"
        case .vi: "Bỏ thay đổi?"
        }
    }

    var keepEditingTitle: String {
        switch self {
        case .en: "Keep editing"
        case .ja: "編集を続ける"
        case .vi: "Sửa tiếp"
        }
    }

    var discardTitle: String {
        switch self {
        case .en: "Discard"
        case .ja: "破棄"
        case .vi: "Bỏ"
        }
    }

    var replaceMemoryDraftTitle: String {
        switch self {
        case .en: "Replace current text?"
        case .ja: "現在の文章を置き換えますか？"
        case .vi: "Thay nội dung đang nhập?"
        }
    }

    var replaceMemoryDraftMessage: String {
        switch self {
        case .en: "This example will replace the text already in the editor."
        case .ja: "この例はエディタ内の文章を置き換えます。"
        case .vi: "Gợi ý này sẽ thay phần đang nhập trong ô soạn."
        }
    }

    var replaceTitle: String {
        switch self {
        case .en: "Replace"
        case .ja: "置き換え"
        case .vi: "Thay"
        }
    }

    var learnedFromChatLabel: String {
        switch self {
        case .en: "Learned from chat"
        case .ja: "チャットから学習"
        case .vi: "Học từ chat"
        }
    }

    var errorTitle: String {
        switch self {
        case .en: "Coach Memory"
        case .ja: "Coach メモリー"
        case .vi: "Bộ nhớ Coach"
        }
    }

    var saveMemoryErrorTitle: String {
        switch self {
        case .en: "Could not save this memory"
        case .ja: "このメモリーを保存できませんでした"
        case .vi: "Không thể lưu ghi nhớ này"
        }
    }

    var memoryTextNotLostMessage: String {
        switch self {
        case .en: "Your text has not been lost."
        case .ja: "入力した文章は失われていません。"
        case .vi: "Nội dung anh nhập chưa bị mất."
        }
    }

    var deleteMemoryErrorMessage: String {
        switch self {
        case .en: "Could not delete this memory. The memory is still available."
        case .ja: "このメモリーを削除できませんでした。メモリーはまだ残っています。"
        case .vi: "Không thể xóa ghi nhớ này. Ghi nhớ vẫn còn."
        }
    }

    var loadMemoryErrorTitle: String {
        switch self {
        case .en: "Could not load Coach Memory"
        case .ja: "Coach メモリーを読み込めませんでした"
        case .vi: "Không thể tải bộ nhớ Coach"
        }
    }

    var tryAgainTitle: String {
        switch self {
        case .en: "Try again"
        case .ja: "再試行"
        case .vi: "Thử lại"
        }
    }

    var addCoachMemoryAccessibilityLabel: String {
        switch self {
        case .en: "Add Coach memory"
        case .ja: "Coach メモリーを追加"
        case .vi: "Thêm ghi nhớ Coach"
        }
    }

    var moreActionsForMemoryAccessibilityLabel: String {
        switch self {
        case .en: "More actions for memory"
        case .ja: "メモリーのその他の操作"
        case .vi: "Thêm thao tác cho ghi nhớ"
        }
    }

    var clearAllCoachMemoryAccessibilityLabel: String {
        switch self {
        case .en: "Clear all Coach Memory"
        case .ja: "すべての Coach メモリーを消去"
        case .vi: "Xóa toàn bộ bộ nhớ Coach"
        }
    }

    var saveMemoryAccessibilityLabel: String {
        switch self {
        case .en: "Save memory"
        case .ja: "メモリーを保存"
        case .vi: "Lưu ghi nhớ"
        }
    }

    var memoryTextFieldAccessibilityLabel: String {
        switch self {
        case .en: "Memory text field"
        case .ja: "メモリー入力欄"
        case .vi: "Ô nhập nội dung ghi nhớ"
        }
    }
}

private extension Bundle {
    var appVersionSummary: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
