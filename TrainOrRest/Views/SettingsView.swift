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
            Section(language.settings.accountSection) {
                NavigationLink {
                    AthleteProfileEditView()
                } label: {
                    settingsRow(language.settings.personalInformation, systemImage: "person", value: athleteSummary)
                }
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    settingsRow(language.settings.languageTitle, systemImage: "globe", value: language.nativeName)
                }
            }

            Section(language.settings.appearanceTitle) {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    settingsRow(language.settings.appearanceTitle, systemImage: "circle.lefthalf.filled", value: language.onboarding.appearanceTitle(appearance))
                }
                .accessibilityLabel(language.settings.changeAppearanceAccessibilityLabel)
            }

            Section(language.settings.connectedServicesSection) {
                settingsRow(language.settings.appleHealth, systemImage: "heart", value: language.settings.connected)
                settingsRow(language.settings.garmin, systemImage: "figure.run", value: language.settings.viaAppleHealth)
                NavigationLink {
                    CalendarsSettingsView()
                } label: {
                    settingsRow(language.settings.calendarsTitle, systemImage: "calendar.badge.clock", value: googleCalendarSummary)
                }
                .accessibilityLabel(language.settings.manageCalendarConnectionsAccessibilityLabel)
                NavigationLink {
                    IntervalsConnectionSettingsView()
                } label: {
                    settingsRow(language.settings.intervalsICU, systemImage: "point.3.connected.trianglepath.dotted", value: intervalsStatusSummary)
                }
                .accessibilityLabel(language.settings.manageIntervalsConnectionAccessibilityLabel)
            }

            Section(language.settings.watchDeliverySection) {
                NavigationLink {
                    WatchDeliverySettingsView()
                } label: {
                    settingsRow(language.settings.watchPush, systemImage: "applewatch.radiowaves.left.and.right", value: watchPushSummary)
                }
            }

            Section(language.settings.coachPersonalizationSection) {
                NavigationLink {
                    CoachMemorySettingsView()
                } label: {
                    settingsRow(language.settings.coachMemoryTitle, systemImage: "brain.head.profile", value: memorySummary)
                }
                NavigationLink {
                    CoachProviderSettingsView()
                } label: {
                    settingsRow(language.settings.coachProviderTitle, systemImage: "sparkles", value: language.settings.modelAndAPI)
                }
            }


            Section(language.settings.dataPrivacySection) {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    settingsRow(language.settings.healthDataPermissions, systemImage: "lock.shield", value: language.settings.iOSSettings)
                }
                settingsRow(language.settings.dataStorage, systemImage: "externaldrive", value: language.settings.onThisDevice)
            }

            Section(language.settings.supportSection) {
                settingsRow(language.settings.aboutTrainOrRest, systemImage: "info.circle", value: Bundle.main.appVersionSummary)
            }
        }
        .navigationTitle(language.settings.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(language.doneLabel) { dismiss() }
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
        if let weight = clean(weightKg) { return language.settings.weightSummary(weight) }
        return language.settings.notComplete
    }

    private var intervalsStatusSummary: String {
        let hasAthlete = !athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasKey = !intervalsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasAthlete && hasKey ? language.settings.connected : language.settings.notConnected
    }

    private var watchPushSummary: String {
        if !watchPushEnabled { return language.settings.off }
        if let last = pushService.lastPushAt { return language.settings.shortDateTime(last) }
        return language.settings.on
    }

    private var googleCalendarSummary: String {
        let connection = googleCalendar.connection()
        switch connection.connectionStatus {
        case .connected: return language.settings.googleConnected
        case .syncing, .initialSync: return language.settings.syncing
        case .needsReconnect, .calendarMissing, .partialFailure: return language.settings.needsAttention
        case .offlineQueued: return language.settings.queued
        default: return language.settings.notConnected
        }
    }

    private var memorySummary: String {
        let count = memoryItems.count
        if count == 0 { return language.settings.empty }
        return language.settings.memoryCount(count)
    }

    private func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CalendarsSettingsView: View {
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

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
                        Text(language.settings.googleCalendar)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
            } footer: {
                Text(language.settings.calendarsFooter)
            }
        }
        .navigationTitle(language.settings.calendarsTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        Form {
            Section {
                AppAppearanceSelector(compact: true)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            } footer: {
                Text(language.settings.appearanceFooter)
            }
        }
        .navigationTitle(language.settings.appearanceTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LanguageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue

    private var selectedLanguage: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }

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
                Text(selectedLanguage.settings.languageFooter)
            }
        }
        .navigationTitle(selectedLanguage.settings.languageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: languageRaw) { _, _ in
            ReadinessWidgetBridge.republishForLanguageChange(in: modelContext)
        }
    }
}

struct IntervalsConnectionSettingsView: View {
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(WorkoutPushSettings.athleteIDKey) private var athleteID = ""
    @AppStorage(WorkoutPushSettings.enabledKey) private var watchPushEnabled = false
    @EnvironmentObject private var pushService: WorkoutPushService
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var status: SettingsStatus?
    @State private var isSyncing = false

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
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
                TextField(language.settings.athleteID, text: $athleteID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    if showAPIKey {
                        TextField(language.settings.apiKey, text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(language.settings.apiKey, text: $apiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                    }
                    Button(showAPIKey ? language.settings.hide : language.settings.reveal) { showAPIKey.toggle() }
                        .font(.caption.weight(.semibold))
                }
                Button {
                    saveConnection()
                } label: {
                    Label(language.settings.saveConnection, systemImage: "checkmark.shield")
                }
                .disabled(!canSave)
                .accessibilityLabel(language.settings.saveIntervalsConnectionAccessibilityLabel)
            } header: {
                Text(language.settings.manageConnection)
            } footer: {
                Text(language.settings.intervalsConnectionFooter)
            }

            Section {
                NavigationLink {
                    WatchDeliverySettingsView()
                } label: {
                    HStack {
                        Text(language.settings.watchPush)
                        Spacer()
                        Text(watchPushEnabled ? language.settings.on : language.settings.off)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
            } footer: {
                Text(language.settings.watchPushManagedFooter)
            }

            if let status {
                Section {
                    SettingsStatusCard(
                        symbol: status.symbol,
                        tint: status.tint,
                        title: status.title,
                        message: status.message,
                        footnote: status.footnote
                    )
                }
            }
        }
        .navigationTitle(language.settings.intervalsICU)
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
                    Text(isConnected ? language.settings.connected : language.settings.connectIntervals)
                        .font(.headline)
                    Text(isConnected ? lastSyncText : language.settings.intervalsSyncDescription)
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
                        Label(language.settings.syncNow, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var lastSyncText: String {
        if pushService.lastPushError != nil { return language.settings.lastSyncFailed }
        if let last = pushService.lastPushAt { return language.settings.lastSync(last) }
        return language.settings.readyToSync
    }

    private var canSave: Bool {
        !athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveConnection() {
        do {
            try KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: KeychainStore.intervalsICUAccount)
            status = SettingsStatus(
                symbol: "checkmark.circle.fill",
                tint: Theme.good,
                title: language.settings.connectionSaved,
                message: language.settings.credentialsStored,
                footnote: watchPushEnabled
                    ? language.settings.deliverPlanPrompt
                    : language.settings.enableWatchPushPrompt
            )
        } catch {
            status = SettingsStatus(
                symbol: "exclamationmark.triangle.fill",
                tint: Theme.bad,
                title: language.settings.couldNotSaveKey,
                message: language.settings.intervalsKeyWriteFailed,
                footnote: language.settings.checkDeviceAccess
            )
        }
    }

    private func syncNow() {
        isSyncing = true
        Task {
            await pushService.reconcile(requireEnabled: false, forceRecreate: true)
            await MainActor.run {
                isSyncing = false
                if let skip = pushService.lastPushSkipReason {
                    status = SettingsStatus(
                        symbol: "pause.circle.fill",
                        tint: Theme.warn,
                        title: language.settings.syncSkipped,
                        message: skip,
                        footnote: nil
                    )
                } else if let error = pushService.lastPushError {
                    status = SettingsStatus(
                        symbol: "exclamationmark.triangle.fill",
                        tint: Theme.bad,
                        title: language.settings.couldNotSync,
                        message: error,
                        footnote: language.settings.checkConnectionAndTryAgain
                    )
                } else {
                    status = SettingsStatus(
                        symbol: "checkmark.circle.fill",
                        tint: Theme.good,
                        title: language.settings.syncComplete,
                        message: language.settings.garminWorkoutsRecreated,
                        footnote: nil
                    )
                }
            }
        }
    }
}

struct WatchDeliverySettingsView: View {
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(WorkoutPushSettings.enabledKey) private var watchPushEnabled = false
    @AppStorage(WorkoutPushSettings.athleteIDKey) private var athleteID = ""
    @EnvironmentObject private var pushService: WorkoutPushService
    @State private var isSyncing = false
    @State private var intervalsConnected = false

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    private var isConnected: Bool {
        intervalsConnected && !athleteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                SettingsStatusCard(
                    symbol: receipt.symbol,
                    tint: receipt.tint,
                    title: receipt.title,
                    message: receipt.message,
                    footnote: receipt.footnote
                )
            }

            Section {
                if !isConnected {
                    NavigationLink {
                        IntervalsConnectionSettingsView()
                    } label: {
                        Label(language.settings.connectIntervals, systemImage: "link.badge.plus")
                    }
                }
                Toggle(language.settings.watchPush, isOn: $watchPushEnabled)
                    .frame(minHeight: 44)
                    .disabled(!isConnected)
                Button {
                    syncNow()
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Label(language.settings.syncNow, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing || !watchPushEnabled || !isConnected)
            } footer: {
                Text(language.settings.watchDeliveryFooter)
            }

            if let report = pushService.lastDebugReport, !report.isEmpty {
                Section {
                    DebugReportView(text: report)
                } header: {
                    Text(language.settings.garminDeliveryDebug)
                } footer: {
                    Text(language.settings.garminDeliveryDebugFooter)
                }
            }
        }
        .navigationTitle(language.settings.watchDeliverySection)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reloadIntervalsKey() }
        .onChange(of: athleteID) { _, _ in reloadIntervalsKey() }
    }

    private func reloadIntervalsKey() {
        let key = (try? KeychainStore.load(account: KeychainStore.intervalsICUAccount)) ?? ""
        intervalsConnected = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var receipt: (symbol: String, tint: Color, title: String, message: String?, footnote: String?) {
        if !isConnected {
            return ("link.badge.plus", Theme.warn, language.settings.intervalsNotConnected,
                    language.settings.connectIntervalsToDeliver, nil)
        }
        if !watchPushEnabled {
            return ("applewatch", Theme.accent, language.settings.watchPushIsOff,
                    language.settings.turnOnWatchPush, nil)
        }
        if let error = pushService.lastPushError {
            return ("exclamationmark.triangle.fill", Theme.bad, language.settings.lastDeliveryFailed,
                    error, language.settings.retrySyncPrompt)
        }
        if let skip = pushService.lastPushSkipReason {
            return ("pause.circle.fill", Theme.warn, language.settings.deliveryPaused, skip, nil)
        }
        if let last = pushService.lastPushAt {
            return ("checkmark.circle.fill", Theme.good, language.settings.workoutsDelivered,
                    language.settings.lastSyncSentence(last), nil)
        }
        return ("applewatch.radiowaves.left.and.right", Theme.accent, language.settings.readyToDeliver,
                language.settings.sendPlanToWatch, nil)
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

/// Compact status receipt used across Settings destinations: icon + headline
/// plus optional body and a tinted next-action line, colored by outcome.
struct SettingsStatusCard: View {
    var symbol: String
    var tint: Color
    var title: String
    var message: String?
    var footnote: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, message, footnote].compactMap { $0 }.joined(separator: ". "))
    }
}

/// Structured outcome backing a `SettingsStatusCard`, set at the call site so
/// tone and next action stay explicit rather than parsed from a message string.
struct SettingsStatus {
    var symbol: String
    var tint: Color
    var title: String
    var message: String?
    var footnote: String?
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
                Text(language.settings.coachMemoryIntro)
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
                    Label(language.settings.addMemoryTitle, systemImage: "plus")
                }
                .accessibilityLabel(language.settings.addCoachMemoryAccessibilityLabel)
            } header: {
                Text(language.settings.rememberedAthleteContextTitle)
            } footer: {
                Text(language.settings.coachMemoryFooter)
            }

            Section {
                Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Label(language.settings.clearAllCoachMemoryTitle, systemImage: "trash")
                }
                .disabled(sortedMemories.isEmpty)
                .accessibilityLabel(language.settings.clearAllCoachMemoryAccessibilityLabel)
            }
        }
        .navigationTitle(language.settings.coachMemoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CoachMemoryEditorView()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(language.settings.addCoachMemoryAccessibilityLabel)
            }
        }
        .task {
            do {
                try PersonalCoachSettings.migrateLegacyCoachMemoryIfNeeded(in: modelContext)
            } catch {
                errorMessage = language.settings.loadMemoryErrorTitle
            }
        }
        .onAppear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: true)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .torSetBottomDockHidden, object: false)
        }
        .alert(language.settings.deleteMemoryConfirmationTitle, isPresented: $isShowingDeleteConfirmation) {
            Button(language.cancelLabel, role: .cancel) { deleteCandidate = nil }
            Button(language.deleteLabel, role: .destructive) { deleteSelectedMemory() }
        } message: {
            Text(language.settings.deleteMemoryConfirmationMessage)
        }
        .alert(language.settings.clearAllConfirmationTitle, isPresented: $isShowingClearConfirmation) {
            Button(language.cancelLabel, role: .cancel) {}
            Button(language.settings.clearAllConfirmationAction, role: .destructive) { clearAllMemories() }
        } message: {
            Text(language.settings.clearAllConfirmationMessage)
        }
        .alert(language.settings.coachMemoryTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(language.settings.tryAgainTitle) {
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
            errorMessage = language.settings.deleteMemoryErrorMessage
        }
        self.deleteCandidate = nil
    }

    private func clearAllMemories() {
        do {
            try PersonalCoachSettings.clearCoachMemory(in: modelContext)
        } catch {
            errorMessage = language.settings.loadMemoryErrorTitle
        }
    }

    private func dateText(for date: Date) -> String {
        language.settings.memoryDate(date)
    }
}

struct CoachProviderSettingsView: View {
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @AppStorage(AdaptivePlanReviewSettings.automaticKey) private var automaticNextWeekReview = false
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

    private var language: CoachLanguage { CoachLanguage(rawValue: languageRaw) ?? .en }
    private var isOpenAI: Bool { CoachModelProvider.isOpenAIModel(model) }

    private var activeKeyPresent: Bool {
        let key = isOpenAI ? openAIAPIKey : anthropicAPIKey
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var receipt: (symbol: String, tint: Color, title: String, message: String?, footnote: String?) {
        if isTesting {
            return ("arrow.triangle.2.circlepath", Theme.accent, language.settings.testingConnection, nil, nil)
        }
        if let status {
            if status == "Connection OK" {
                return ("checkmark.circle.fill", Theme.good, language.settings.coachConnected,
                        language.settings.modelReady(language.settings.modelLabel(model)), nil)
            }
            return ("exclamationmark.triangle.fill", Theme.bad, language.settings.connectionFailed,
                    status, language.settings.checkKeyAndConnectAgain)
        }
        if activeKeyPresent {
            return ("key.fill", Theme.accent, language.settings.coachKeySaved,
                    language.settings.modelSelected(language.settings.modelLabel(model)), nil)
        }
        return ("sparkles", Theme.warn, language.settings.addCoachKey,
                language.settings.coachKeyRecommendation, nil)
    }

    var body: some View {
        Form {
            Section {
                SettingsStatusCard(
                    symbol: receipt.symbol,
                    tint: receipt.tint,
                    title: receipt.title,
                    message: receipt.message,
                    footnote: receipt.footnote
                )
            }

            Section {
                Toggle(
                    language.plan.automaticNextWeekReview(provider: CoachModelProvider.displayName(for: model)),
                    isOn: $automaticNextWeekReview
                )
                if !activeKeyPresent {
                    Label(language.plan.addKeyForSelectedProvider, systemImage: "key")
                        .foregroundStyle(Theme.dim)
                }
            } header: {
                Text(language.plan.nextWeekReviewSettingsTitle)
            } footer: {
                Text(language.plan.nextWeekReviewDisclosure(provider: CoachModelProvider.displayName(for: model)))
            }

            Section {
                SecureField(language.settings.anthropicAPIKey, text: $anthropicAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button {
                    saveAndTestAnthropic()
                } label: {
                    if isTesting {
                        ProgressView()
                    } else {
                        Label(language.settings.connectCoach, systemImage: "checkmark.shield")
                    }
                }
                .disabled(anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
            } header: {
                Text(language.settings.recommendedCoach)
            } footer: {
                Text(language.settings.recommendedCoachFooter)
            }

            Section {
                DisclosureGroup(language.settings.advancedProviderSetup) {
                    Picker(language.settings.model, selection: $model) {
                        Section(language.settings.claude) {
                            ForEach(anthropicModels, id: \.self) { Text(language.settings.modelLabel($0)).tag($0) }
                        }
                        Section(language.settings.openAI) {
                            ForEach(openAIModels, id: \.self) { Text(language.settings.modelLabel($0)).tag($0) }
                        }
                    }
                    SecureField(language.settings.openAIAPIKey, text: $openAIAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    Button {
                        saveAndTestOpenAI()
                    } label: {
                        if isTesting {
                            ProgressView()
                        } else {
                            Label(language.settings.saveOpenAIAndTest, systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
                }
            } footer: {
                Text(language.settings.advancedProviderFooter)
            }
        }
        .navigationTitle(language.settings.coachProviderNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            anthropicAPIKey = (try? KeychainStore.load()) ?? ""
            openAIAPIKey = (try? KeychainStore.load(account: KeychainStore.openAIAPIKeyAccount)) ?? ""
        }
        .onChange(of: model) { _, _ in status = nil }
        .onChange(of: anthropicAPIKey) { _, _ in status = nil }
        .onChange(of: openAIAPIKey) { _, _ in status = nil }
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
                status = language.settings.couldNotSaveOpenAIAPIKey
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
                status = language.settings.couldNotSaveAnthropicAPIKey
            }
            isTesting = false
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
                            Text(language.settings.learnedFromChatLabel)
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
                        Label(language.settings.editMemoryTitle, systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(language.deleteLabel, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(language.settings.moreActionsForMemoryAccessibilityLabel)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.settings.memoryCardAccessibilityLabel(text: item.text, dateText: dateText))
    }
}

private struct CoachMemoryEmptyState: View {
    let language: CoachLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(language.settings.noCoachMemoriesTitle, systemImage: "brain.head.profile")
                .font(.headline)
            Text(language.settings.noCoachMemoriesMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                CoachMemoryEditorView()
            } label: {
                Label(language.settings.addMemoryTitle, systemImage: "plus")
            }
            .accessibilityLabel(language.settings.addCoachMemoryAccessibilityLabel)
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
                    Text(language.settings.memoryEditorIntro)
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
                        .accessibilityLabel(language.settings.memoryTextFieldAccessibilityLabel)
                    if draft.isEmpty {
                        Text(language.settings.memoryEditorPlaceholder)
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
                ForEach(language.settings.coachMemorySuggestedExamples, id: \.self) { example in
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
                Text(language.settings.suggestedExamplesTitle)
            }

            if let errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage)
                            .foregroundStyle(Theme.bad)
                        Text(language.settings.memoryTextNotLostMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(language.settings.tryAgainTitle) { save() }
                    }
                }
            }
        }
        .navigationTitle(isEditing ? language.settings.editMemoryTitle : language.settings.addMemoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(language.backLabel) { back() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(language.saveLabel)
                    }
                }
                .disabled(!canSave)
                .accessibilityLabel(language.settings.saveMemoryAccessibilityLabel)
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
        .alert(language.settings.replaceMemoryDraftTitle, isPresented: $isShowingReplaceConfirmation) {
            Button(language.cancelLabel, role: .cancel) { pendingExample = nil }
            Button(language.settings.replaceTitle) {
                if let pendingExample {
                    draft = pendingExample
                }
                pendingExample = nil
            }
        } message: {
            Text(language.settings.replaceMemoryDraftMessage)
        }
        .alert(language.settings.discardChangesTitle, isPresented: $isShowingDiscardConfirmation) {
            Button(language.settings.keepEditingTitle, role: .cancel) {}
            Button(language.settings.discardTitle, role: .destructive) { dismiss() }
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
            errorMessage = language.settings.saveMemoryErrorTitle
        }
    }
}

extension Notification.Name {
    static let torSetBottomDockHidden = Notification.Name("torSetBottomDockHidden")
    static let torOpenCoachChat = Notification.Name("torOpenCoachChat")
}


private extension Bundle {
    var appVersionSummary: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
