import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(PersonalCoachSettings.storageKey) private var personalCoachNotes = ""
    @AppStorage(PersonalCoachSettings.weightKgKey) private var weightKg = ""
    @AppStorage(WorkoutPushSettings.enabledKey) private var watchPushEnabled = false
    @AppStorage(WorkoutPushSettings.athleteIDKey) private var athleteID = ""

    @EnvironmentObject private var pushService: WorkoutPushService
    @Environment(\.dismiss) private var dismiss
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

    private var memorySummary: String {
        let notes = PersonalCoachSettings.sanitizedNotes(personalCoachNotes)
        return notes.isEmpty ? "Empty" : "1 note"
    }

    private func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
                Text("Credentials stay in the device keychain. Enable Garmin upload in intervals.icu if you expect workouts to appear on supported devices.")
            }

            if let status {
                Section {
                    Text(status)
                        .foregroundStyle(status.hasPrefix("Could not") ? Theme.bad : Theme.good)
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
        if let error = pushService.lastPushError { return "Last sync failed" }
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
            await pushService.reconcile()
            await MainActor.run {
                isSyncing = false
                status = pushService.lastPushError == nil ? "Sync complete." : "Could not sync intervals.icu."
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
        }
        .navigationTitle("Watch Delivery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncNow() {
        isSyncing = true
        Task {
            await pushService.reconcile()
            await MainActor.run { isSyncing = false }
        }
    }
}

struct CoachMemorySettingsView: View {
    @AppStorage(PersonalCoachSettings.storageKey) private var notes = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $notes)
                    .frame(minHeight: 160)
                    .autocorrectionDisabled()
                    .onChange(of: notes) { _, newValue in
                        let sanitized = PersonalCoachSettings.sanitizedNotes(newValue)
                        if sanitized != newValue { notes = sanitized }
                    }
            } header: {
                Text("Remembered athlete context")
            } footer: {
                Text("Coach uses this local note to keep stable context such as injuries, fueling, scheduling constraints, and preferences. Clear it to remove remembered context.")
            }
            Section {
                Button(role: .destructive) { notes = "" } label: {
                    Label("Clear coach memory", systemImage: "trash")
                }
                .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Coach Memory")
        .navigationBarTitleDisplayMode(.inline)
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

private extension Bundle {
    var appVersionSummary: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
