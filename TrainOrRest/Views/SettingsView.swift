import SwiftUI

struct SettingsView: View {
    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
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
