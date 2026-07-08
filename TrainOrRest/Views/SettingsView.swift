import SwiftUI

struct SettingsView: View {
    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @AppStorage(CoachLanguage.storageKey) private var languageRaw = CoachLanguage.en.rawValue
    @Environment(\.dismiss) private var dismiss
    @StateObject private var chatStore = CoachChatStore()
    @State private var apiKey = ""
    @State private var status: String?
    @State private var isTesting = false

    private let models = [
        CoachChatConfig.defaultModel,
        "claude-haiku-4-5",
        "claude-opus-4-8"
    ]

    var body: some View {
        Form {
            Section("Claude API") {
                SecureField("Anthropic API key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Picker("Model", selection: $model) {
                    ForEach(models, id: \.self) { Text(modelLabel($0)).tag($0) }
                }
                Button {
                    saveAndTest()
                } label: {
                    if isTesting {
                        ProgressView()
                    } else {
                        Label("Save and Test", systemImage: "checkmark.shield")
                    }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
            }
            if let status {
                Section {
                    Text(status)
                        .foregroundStyle(status == "Connection OK" ? .green : .secondary)
                }
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
            apiKey = (try? KeychainStore.load()) ?? ""
        }
    }

    private func saveAndTest() {
        isTesting = true
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try KeychainStore.save(trimmed)
                status = await chatStore.testConnection(apiKey: trimmed, model: model)
            } catch {
                status = "Could not save API key."
            }
            isTesting = false
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
        case CoachChatConfig.defaultModel:
            "Balanced coach"
        case "claude-haiku-4-5":
            "Fast coach"
        case "claude-opus-4-8":
            "Deep review coach"
        default:
            id
        }
    }
}
