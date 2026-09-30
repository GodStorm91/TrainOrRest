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
    private enum KeyCheck: Equatable {
        case testing(CoachConnection)
        case finished(CoachConnection, ClaudeKeyTestOutcome)
    }

    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(CoachConnection.storageKey) private var connectionRaw = CoachConnection.chatGPT.rawValue
    @AppStorage(CoachConnection.chatGPT.modelStorageKey) private var chatGPTModel = ""
    @AppStorage(CoachConnection.anthropicKey.modelStorageKey) private var claudeModel = CoachChatConfig.defaultModel
    @AppStorage(CoachConnection.openAIKey.modelStorageKey) private var openAIModel = CoachChatConfig.defaultOpenAIModel
    @AppStorage(CoachConnection.grok.modelStorageKey) private var grokModel = GrokAuthConfiguration.defaultModel
    @AppStorage(AdaptivePlanReviewSettings.automaticKey) private var automaticNextWeekReview = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var chatStore = CoachChatStore()
    @State private var anthropicAPIKey = ""
    @State private var openAIAPIKey = ""
    @State private var hasAnthropicKey = false
    @State private var hasOpenAIKey = false
    @State private var chatGPTState = ChatGPTTokenStore.shared.state
    @State private var grokState = GrokTokenStore.shared.state
    @State private var isSigningInWithGrok = false
    @State private var grokSignInError: String?
    @State private var chatGPTModels: [ChatGPTModel] = []
    @State private var keyCheck: KeyCheck?
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var showsNotAClaudeKey = false
    @State private var awaitingKeyReturn = false
    @State private var highlightsPaste = false
    @State private var showsPlanNotice = false
    @State private var showsChatGPTDiagnostics = false
    @State private var isRunningChatGPTProbe = false
    @State private var chatGPTProbeSummary: [String] = []
    @State private var chatGPTDiagnosticsReport = ""

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
    private var copy: SettingsCopy { language.settings }
    private var connection: CoachConnection { CoachConnection(rawValue: connectionRaw) ?? .chatGPT }
    private var isTesting: Bool {
        if case .testing = keyCheck { return true }
        return false
    }

    private var status: CoachConnectionStatus {
        CoachConnectionStatus(
            selected: connection,
            chatGPT: chatGPTState,
            hasAnthropicKey: hasAnthropicKey,
            hasOpenAIKey: hasOpenAIKey,
            grok: grokState
        )
    }

    private var chatGPTStatus: CoachConnectionStatus {
        CoachConnectionStatus(selected: .chatGPT, chatGPT: chatGPTState, hasAnthropicKey: false, hasOpenAIKey: false)
    }

    private var usableConnections: [CoachConnection] {
        var connections: [CoachConnection] = []
        if chatGPTStatus.isConnected { connections.append(.chatGPT) }
        if hasAnthropicKey { connections.append(.anthropicKey) }
        if hasOpenAIKey { connections.append(.openAIKey) }
        if case .connected = grokState { connections.append(.grok) }
        return connections
    }

    private var statusModelName: String? {
        switch connection {
        case .chatGPT:
            guard !chatGPTModel.isEmpty else { return nil }
            return chatGPTModels.first { $0.id == chatGPTModel }?.displayName ?? chatGPTModel
        case .anthropicKey: return claudeModel
        case .openAIKey: return openAIModel
        case .grok: return grokModel
        }
    }

    private var receipt: SettingsStatus {
        switch keyCheck {
        case .testing:
            return SettingsStatus(symbol: "arrow.triangle.2.circlepath", tint: Theme.accent, title: copy.testingConnection)
        case .finished(let checked, .connected):
            let model = checked == .openAIKey ? openAIModel : claudeModel
            return SettingsStatus(symbol: "checkmark.circle.fill", tint: Theme.good, title: copy.coachConnected,
                                  message: copy.modelReady(copy.modelLabel(model)))
        case .finished(let checked, let outcome):
            return SettingsStatus(symbol: "exclamationmark.triangle.fill", tint: Theme.bad, title: copy.connectionFailed,
                                  message: failureMessage(outcome, connection: checked))
        case nil:
            break
        }
        if let grokSignInError {
            return SettingsStatus(symbol: "exclamationmark.triangle.fill", tint: Theme.bad,
                                  title: copy.grokSignInFailed, message: grokSignInError)
        }
        if let signInError {
            return SettingsStatus(symbol: "exclamationmark.triangle.fill", tint: Theme.bad,
                                  title: copy.chatGPTSignInFailed, message: signInError)
        }
        let status = status
        let tint: Color = status.isConnected ? Theme.good : (status.kind == .notConnected ? Theme.warn : Theme.bad)
        return SettingsStatus(symbol: status.symbol, tint: tint, title: status.title(copy),
                              message: status.message(copy, model: statusModelName))
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
                if usableConnections.count > 1 {
                    Picker(copy.coachConnectionPicker, selection: $connectionRaw) {
                        ForEach(usableConnections, id: \.self) { option in
                            Text(pickerLabel(option)).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                Toggle(
                    language.plan.automaticNextWeekReview(provider: connection.displayName),
                    isOn: $automaticNextWeekReview
                )
                if !status.isConnected {
                    Label(language.plan.connectCoachFirst, systemImage: "bubble.left.and.text.bubble.right")
                        .foregroundStyle(Theme.dim)
                }
            } header: {
                Text(language.plan.nextWeekReviewSettingsTitle)
            } footer: {
                Text(language.plan.nextWeekReviewDisclosure(provider: connection.displayName))
            }

            chatGPTSection
            if showsChatGPTDiagnostics, chatGPTState != .signedOut {
                chatGPTDiagnosticsSection
            }
            grokSection
            claudeSection

            Section {
                DisclosureGroup(copy.advancedProviderSetup) {
                    Picker(copy.claudeModel, selection: $claudeModel) {
                        ForEach(anthropicModels, id: \.self) { Text(copy.modelLabel($0)).tag($0) }
                    }
                    Picker(copy.openAIModel, selection: $openAIModel) {
                        ForEach(openAIModels, id: \.self) { Text(copy.modelLabel($0)).tag($0) }
                    }
                    SecureField(copy.openAIAPIKey, text: $openAIAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    Button {
                        saveAndTest(.openAIKey)
                    } label: {
                        if isTesting {
                            ProgressView()
                        } else {
                            Label(copy.saveOpenAIAndTest, systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
                }
            } footer: {
                Text(copy.advancedOpenAIFooter)
            }
        }
        .navigationTitle(copy.coachProviderNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .chatGPTPlanNotice(isPresented: $showsPlanNotice, copy: copy)
        .task {
            anthropicAPIKey = (try? KeychainStore.load()) ?? ""
            openAIAPIKey = (try? KeychainStore.load(account: KeychainStore.openAIAPIKeyAccount)) ?? ""
            refreshStoredKeys()
            showsChatGPTDiagnostics = await ChatGPTDiagnostics.isAvailableInThisBuild()
            refreshChatGPTDiagnosticsReport()
        }
        .task(id: chatGPTState) { await loadChatGPTModels() }
        .onReceive(ChatGPTTokenStore.shared.statePublisher.receive(on: DispatchQueue.main)) { chatGPTState = $0 }
        .onReceive(GrokTokenStore.shared.statePublisher.receive(on: DispatchQueue.main)) { grokState = $0 }
        .onChange(of: claudeModel) { _, _ in clearFinishedKeyCheck() }
        .onChange(of: openAIModel) { _, _ in clearFinishedKeyCheck() }
        .onChange(of: anthropicAPIKey) { _, _ in clearFinishedKeyCheck() }
        .onChange(of: openAIAPIKey) { _, _ in clearFinishedKeyCheck() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, awaitingKeyReturn else { return }
            awaitingKeyReturn = false
            highlightsPaste = UIPasteboard.general.hasStrings
        }
    }

    /// Editing a key or model invalidates the last result, but never an in-flight test (a paste starts one).
    private func clearFinishedKeyCheck() {
        if !isTesting { keyCheck = nil }
    }

    private var chatGPTSection: some View {
        Section {
            switch chatGPTState {
            case .signedOut, .notEligible:
                ContinueWithChatGPTButton(title: copy.continueWithChatGPT, isWorking: isSigningIn) {
                    signIn(requestConsent: false)
                }
            case .connected:
                if !chatGPTModels.isEmpty {
                    Picker(copy.model, selection: $chatGPTModel) {
                        ForEach(chatGPTModels) { Text($0.displayName).tag($0.id) }
                    }
                }
                Link(copy.manageUsage, destination: CoachConnectionStatus.usageURL)
            case .planUsageDisabled, .needsReconnect, .usageLimited:
                ChatGPTStatusActions(status: chatGPTStatus, copy: copy, isWorking: isSigningIn) { consent in
                    signIn(requestConsent: consent)
                }
            }
            if chatGPTState != .signedOut {
                Button(copy.disconnectChatGPT, role: .destructive) { disconnectChatGPT() }
            }
        } header: {
            Text(copy.useChatGPTPlanHeader)
        } footer: {
            Text(copy.chatGPTPrivacyFooter)
        }
    }
    private var grokSection: some View {
        Section {
            switch grokState {
            case .signedOut:
                Button {
                    startGrokSignIn()
                } label: {
                    if isSigningInWithGrok {
                        ProgressView()
                    } else {
                        Label(copy.signInWithGrok, systemImage: "person.crop.circle.badge.plus")
                    }
                }
                .disabled(isSigningInWithGrok)
            case .authorizing(let userCode, let url):
                Text(copy.grokEnterCode)
                Text(userCode)
                    .font(.title2.monospaced())
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = userCode
                } label: {
                    Label(copy.copyCode, systemImage: "doc.on.doc")
                }
                Link(copy.openGrokVerification, destination: url)
                Button(copy.cancelGrokSignIn, role: .cancel) {
                    cancelGrokSignIn()
                }
            case .connected:
                Picker(copy.model, selection: $grokModel) {
                    ForEach(GrokAuthConfiguration.models, id: \.self) { Text($0).tag($0) }
                }
                Button(copy.disconnectGrok, role: .destructive) { disconnectGrok() }
            case .needsReconnect:
                Button(copy.reconnect) { startGrokSignIn() }
                    .disabled(isSigningInWithGrok)
                Button(copy.disconnectGrok, role: .destructive) { disconnectGrok() }
            }
            if let grokSignInError {
                Text(grokSignInError)
                    .font(.footnote)
                    .foregroundStyle(Theme.bad)
            }
        } header: {
            Text(copy.grokHeader)
        } footer: {
            Text(copy.grokPrivacyFooter)
        }
    }


    private var chatGPTDiagnosticsSection: some View {
        Section {
            Button {
                runChatGPTProbe()
            } label: {
                if isRunningChatGPTProbe {
                    ProgressView()
                } else {
                    Label(copy.runChatGPTDiagnostics, systemImage: "stethoscope")
                }
            }
            .disabled(isRunningChatGPTProbe)
            if !chatGPTDiagnosticsReport.isEmpty {
                Button {
                    UIPasteboard.general.string = chatGPTDiagnosticsReport
                } label: {
                    Label(copy.copyDiagnosticsReport, systemImage: "doc.on.doc")
                }
                ShareLink(item: chatGPTDiagnosticsReport)
                DebugReportView(text: String(chatGPTDiagnosticsReport.prefix(6_000)))
                Button(copy.clearDiagnosticsLog, role: .destructive) {
                    ChatGPTDiagnostics.shared.clear()
                    chatGPTProbeSummary = []
                    refreshChatGPTDiagnosticsReport()
                }
            }
        } header: {
            Text(copy.chatGPTDiagnosticsHeader)
        } footer: {
            Text(copy.chatGPTDiagnosticsFooter)
        }
    }

    private func runChatGPTProbe() {
        isRunningChatGPTProbe = true
        Task {
            chatGPTProbeSummary = await ChatGPTDiagnosticsProbe.run(selectedModel: chatGPTModel)
            isRunningChatGPTProbe = false
            chatGPTState = ChatGPTTokenStore.shared.state
            refreshChatGPTDiagnosticsReport()
        }
    }

    private func refreshChatGPTDiagnosticsReport() {
        let diagnostics = ChatGPTDiagnostics.shared
        guard !diagnostics.entries.isEmpty || !chatGPTProbeSummary.isEmpty else {
            chatGPTDiagnosticsReport = ""
            return
        }
        let info = Bundle.main.infoDictionary
        let summary = chatGPTProbeSummary.isEmpty
            ? ["TrainOrRest \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
               "automatic weekly review: \(automaticNextWeekReview)"]
            : chatGPTProbeSummary + ["automatic weekly review: \(automaticNextWeekReview)"]
        chatGPTDiagnosticsReport = diagnostics.report(summary: summary)
    }

    private var claudeSection: some View {
        Section {
            HStack {
                SecureField(copy.anthropicAPIKey, text: $anthropicAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                PasteButton(payloadType: String.self) { strings in
                    let pasted = strings.first ?? ""
                    Task { @MainActor in handlePastedClaudeKey(pasted) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .tint(highlightsPaste ? Theme.accent : .gray)
                .accessibilityLabel(copy.pasteKey)
            }
            if showsNotAClaudeKey {
                Text(copy.notAClaudeKey)
                    .font(.footnote)
                    .foregroundStyle(Theme.warn)
            }
            Button {
                saveAndTest(.anthropicKey)
            } label: {
                if isTesting {
                    ProgressView()
                } else {
                    Label(copy.connectCoach, systemImage: "checkmark.shield")
                }
            }
            .disabled(anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
            if case .finished(.anthropicKey, .needsCredits) = keyCheck {
                Link(copy.addCredits, destination: ClaudeKeyTestOutcome.billingURL)
            }
            VStack(alignment: .leading, spacing: 2) {
                Button(copy.getClaudeKey) {
                    awaitingKeyReturn = true
                    openURL(ClaudeKeyTestOutcome.keysURL)
                }
                Text(copy.getClaudeKeySteps)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(copy.useClaudeKeyHeader)
        } footer: {
            Text(copy.claudeBillingFooter)
        }
    }

    private func pickerLabel(_ option: CoachConnection) -> String {
        option == .openAIKey ? copy.openAIKeyConnection : option.displayName
    }

    private func failureMessage(_ outcome: ClaudeKeyTestOutcome, connection: CoachConnection) -> String {
        switch outcome {
        case .connected: copy.coachConnected
        case .rejected: connection == .anthropicKey ? copy.claudeKeyRejected : copy.checkKeyAndConnectAgain
        case .needsCredits: copy.claudeNeedsCredits
        case .rateLimited: copy.coachRateLimited
        case .offline: copy.coachOffline
        case .failed(let message): message
        }
    }

    private func refreshStoredKeys() {
        hasAnthropicKey = CoachCredentialResolver.isConnected(.anthropicKey)
        hasOpenAIKey = CoachCredentialResolver.isConnected(.openAIKey)
    }

    private func loadChatGPTModels() async {
        guard case .connected = chatGPTState else {
            chatGPTModels = []
            return
        }
        chatGPTModels = (try? await ChatGPTModelCatalog.shared.models(tokenProvider: ChatGPTTokenStore.shared)) ?? []
        _ = try? await ChatGPTModelCatalog.shared.resolveSelectedModel(tokenProvider: ChatGPTTokenStore.shared)
    }

    private func handlePastedClaudeKey(_ pasted: String) {
        highlightsPaste = false
        guard let key = ClaudeKeyTestOutcome.claudeKey(fromPasted: pasted) else {
            anthropicAPIKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            showsNotAClaudeKey = true
            return
        }
        showsNotAClaudeKey = false
        anthropicAPIKey = key
        saveAndTest(.anthropicKey)
    }

    private func signIn(requestConsent: Bool) {
        isSigningIn = true
        signInError = nil
        keyCheck = nil
        Task {
            let outcome = await ChatGPTSignInAction.run(requestConsent: requestConsent)
            isSigningIn = false
            chatGPTState = ChatGPTTokenStore.shared.state
            switch outcome {
            case .connected:
                if case .connected = chatGPTState, ChatGPTSignInAction.shouldShowPlanNotice() {
                    showsPlanNotice = true
                }
            case .cancelled:
                break
            case .failed(let message):
                signInError = message
            }
        }
    }

    private func disconnectChatGPT() {
        signInError = nil
        Task {
            await ChatGPTTokenStore.shared.signOut()
            await ChatGPTModelCatalog.shared.invalidate()
            chatGPTState = ChatGPTTokenStore.shared.state
            guard connection == .chatGPT else { return }
            if hasAnthropicKey {
                connectionRaw = CoachConnection.anthropicKey.rawValue
            } else if hasOpenAIKey {
                connectionRaw = CoachConnection.openAIKey.rawValue
            }
        }
    }
    private func startGrokSignIn() {
        isSigningInWithGrok = true
        grokSignInError = nil
        Task {
            defer { isSigningInWithGrok = false }
            do {
                try await GrokTokenStore.shared.signIn { authorization in
                    Task { @MainActor in
                        openURL(authorization.verificationURL)
                    }
                }
                connectionRaw = CoachConnection.grok.rawValue
                grokState = GrokTokenStore.shared.state
            } catch is CancellationError {
                return
            } catch let error as GrokOAuthError where error == .cancelled {
                return
            } catch {
                grokSignInError = error.localizedDescription
                grokState = GrokTokenStore.shared.state
            }
        }
    }

    private func cancelGrokSignIn() {
        Task {
            await GrokTokenStore.shared.cancelSignIn()
            grokState = GrokTokenStore.shared.state
            isSigningInWithGrok = false
        }
    }

    private func disconnectGrok() {
        grokSignInError = nil
        Task {
            await GrokTokenStore.shared.signOut()
            grokState = GrokTokenStore.shared.state
            guard connection == .grok else { return }
            if case .connected = chatGPTState {
                connectionRaw = CoachConnection.chatGPT.rawValue
            } else if hasAnthropicKey {
                connectionRaw = CoachConnection.anthropicKey.rawValue
            } else if hasOpenAIKey {
                connectionRaw = CoachConnection.openAIKey.rawValue
            }
        }
    }


    private func saveAndTest(_ keyConnection: CoachConnection) {
        guard let account = keyConnection.apiKeyAccount else { return }
        let field = keyConnection == .openAIKey ? openAIAPIKey : anthropicAPIKey
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = keyConnection == .openAIKey ? openAIModel : claudeModel
        signInError = nil
        keyCheck = .testing(keyConnection)
        Task {
            do {
                try KeychainStore.save(trimmed, account: account)
            } catch {
                keyCheck = .finished(keyConnection, .failed(
                    keyConnection == .openAIKey ? copy.couldNotSaveOpenAIAPIKey : copy.couldNotSaveAnthropicAPIKey
                ))
                return
            }
            refreshStoredKeys()
            connectionRaw = keyConnection.rawValue
            let error = await chatStore.testConnection(
                CoachAccess(connection: keyConnection, credential: .apiKey(trimmed)),
                model: model
            )
            keyCheck = .finished(keyConnection, ClaudeKeyTestOutcome(error: error))
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
