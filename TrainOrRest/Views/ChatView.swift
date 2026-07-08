import SwiftData
import SwiftUI

struct ChatView: View {
    @AppStorage("coachModel") private var model = CoachChatConfig.defaultModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.date) private var messages: [ChatMessage]
    @StateObject private var chatStore = CoachChatStore()
    @State private var draft = ""
    @State private var hasAPIKey = false

    var body: some View {
        VStack(spacing: 0) {
            if !hasAPIKey {
                missingKeyView
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "Ask Your Coach",
                    systemImage: "message.badge.waveform",
                    description: Text("Ask why today's workout is scheduled, or request a change. Plan edits are checked before they are applied.")
                )
            } else {
                List(messages) { message in
                    ChatBubble(message: message)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
            composer
        }
        .navigationTitle("Coach")
        .toolbar {
            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
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
                    .background(.red, in: Capsule())
                    .padding(.top, 4)
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

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasAPIKey {
                Label("Coach suggestions are validated before your plan changes.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about today's run or request a checked adjustment", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    send()
                } label: {
                    if chatStore.isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasAPIKey || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatStore.isSending)
            }
        }
        .padding()
        .background(.bar)
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            await chatStore.send(text: text, model: model, in: modelContext)
        }
    }

    private func refreshKeyState() {
        hasAPIKey = !((try? KeychainStore.load()) ?? "").isEmpty
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            Text(message.text)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(message.role == .user ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
                }
            if let applied = message.appliedAdjustment {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Validated plan update", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                    Text(applied)
                        .font(.caption)
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
