import SwiftUI

struct SettingsView: View {
    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @AppStorage(PersonalCoachSettings.ageKey) private var personalAge = ""
    @AppStorage(PersonalCoachSettings.heightCmKey) private var personalHeightCm = ""
    @AppStorage(PersonalCoachSettings.weightKgKey) private var personalWeightKg = ""
    @AppStorage(PersonalCoachSettings.storageKey) private var personalCoachNotes = ""
    @Environment(\.dismiss) private var dismiss
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
            Section {
                AppAppearanceSelector(compact: true)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Appearance")
            } footer: {
                Text("Use System follows the appearance setting of this iPhone. Light and Dark are manual overrides you can change anytime.")
            }
            Section {
                labeledNumberField("Age", value: $personalAge, unit: "years", allowsDecimal: false)
                labeledNumberField("Height", value: $personalHeightCm, unit: "cm", allowsDecimal: true)
                labeledNumberField("Weight", value: $personalWeightKg, unit: "kg", allowsDecimal: true)
                TextEditor(text: $personalCoachNotes)
                    .frame(minHeight: 80)
                    .autocorrectionDisabled()
                    .onChange(of: personalCoachNotes) { _, newValue in
                        let sanitized = PersonalCoachSettings.sanitizedNotes(newValue)
                        if sanitized != newValue { personalCoachNotes = sanitized }
                    }
            } header: {
                Text("Personal coach settings")
            } footer: {
                Text("Age is sent as years, height as cm, weight as kg. Notes are also attached to every coach message for stable context like diet, injuries, supplements, and coaching preferences.")
            }
            Section {
                NavigationLink {
                    ProfileView()
                } label: {
                    Label("Profile", systemImage: "person")
                }
                .accessibilityLabel("Profile")
            }
            Section {
                ForEach(CoachLanguage.allCases) { language in
                    languageRow(language)
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Coach chat and suggestions will use this language.")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            Button("Done") { dismiss() }
        }
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

    private func labeledNumberField(
        _ title: String,
        value: Binding<String>,
        unit: String,
        allowsDecimal: Bool
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: value)
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: value.wrappedValue) { _, newValue in
                    let sanitized = PersonalCoachSettings.sanitizedNumber(newValue, allowsDecimal: allowsDecimal)
                    if sanitized != newValue { value.wrappedValue = sanitized }
                }
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func languageRow(_ language: CoachLanguage) -> some View {
        Button {
            languageRaw = language.rawValue
        } label: {
            HStack(spacing: 12) {
                Text(language.flag).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.nativeName)
                        .font(.body)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
