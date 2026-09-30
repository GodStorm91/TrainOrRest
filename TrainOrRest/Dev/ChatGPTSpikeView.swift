#if DEBUG
import SwiftUI
import UIKit

/// Device check for the ChatGPT sign-in path: drives the shipping token store, model catalog,
/// and Responses client and prints what each step returned. Never prints tokens.
/// Launch with `TOR_DEV_SEED=1 TOR_DEV_SCREEN=chatGPTSpike` on a real iPhone.
struct ChatGPTSpikeView: View {
    @State private var log: [String] = []
    @State private var isRunning = false

    var body: some View {
        List {
            Section {
                Button("1. Sign in with ChatGPT") { run(signIn) }
                Button("2. List models") { run(listModels) }
                Button("3. Forced coach_response turn with image") { run { await coachTurn(forced: true) } }
                Button("4. Unforced turn with tools") { run { await coachTurn(forced: false) } }
                Button("5. Refresh after unauthorized") { run(forceRefresh) }
                Button("6. Sign out and revoke", role: .destructive) { run(signOut) }
            }
            .disabled(isRunning)
            Section("State: \(String(describing: ChatGPTTokenStore.shared.state))") {
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("ChatGPT spike")
        .toolbar { Button("Clear") { log.removeAll() } }
    }

    private func run(_ step: @escaping () async -> Void) {
        isRunning = true
        Task {
            await step()
            isRunning = false
        }
    }

    private func append(_ line: String) {
        log.append(line)
        print("[ChatGPTSpike] \(line)")
    }

    private func signIn() async {
        let started = Date()
        let outcome = await ChatGPTSignInAction.run()
        append("sign-in: \(outcome) in \(Int(Date().timeIntervalSince(started)))s")
        append("state: \(ChatGPTTokenStore.shared.state), email present: \(ChatGPTTokenStore.shared.email != nil)")
    }

    private func listModels() async {
        do {
            let models = try await ChatGPTModelCatalog.shared.models(tokenProvider: ChatGPTTokenStore.shared, forceRefresh: true)
            append("listed models: \(models.map(\.id).joined(separator: ", "))")
            let selected = try await ChatGPTModelCatalog.shared.resolveSelectedModel(tokenProvider: ChatGPTTokenStore.shared)
            append("selected model: \(selected)")
        } catch {
            append("models failed: \(error)")
        }
    }

    private func coachTurn(forced: Bool) async {
        let request = ClaudeRequest(
            model: CoachCredentialResolver.model(for: .chatGPT),
            system: "You are a running coach. Answer through the coach_response tool.",
            tools: [CoachToolCatalog.coachResponse],
            toolChoice: forced ? .tool(name: CoachToolCatalog.coachResponseName) : nil,
            messages: [ClaudeMessageParam(role: "user", content: [
                .image(mediaType: "image/jpeg", data: Self.sampleImageBase64),
                .text("What color is this image? Then give one sentence of advice for an easy run.")
            ])]
        )
        var kinds: [String] = []
        var toolJSONBytes = 0
        var text = ""
        do {
            let stream = try await ChatGPTResponsesClient().stream(request, credential: .chatGPT(ChatGPTTokenStore.shared))
            for try await event in stream {
                switch event {
                case .contentBlockStart(_, let kind): kinds.append("blockStart(\(kind))")
                case .textDelta(_, let delta): text += delta
                case .inputJSONDelta(_, let delta): toolJSONBytes += delta.utf8.count
                case .messageDelta(let stopReason): kinds.append("messageDelta(\(stopReason ?? "nil"))")
                default: kinds.append(String(describing: event))
                }
            }
            append("turn forced=\(forced) completed; events: \(kinds.joined(separator: " "))")
            append("text chars: \(text.count), tool JSON bytes: \(toolJSONBytes)")
        } catch {
            append("turn forced=\(forced) failed: \(error)")
        }
    }

    private func forceRefresh() async {
        do {
            _ = try await ChatGPTTokenStore.shared.refreshAfterUnauthorized()
            append("refresh ok (rotated token stored)")
        } catch {
            append("refresh failed: \(error)")
        }
    }

    private func signOut() async {
        let revoked = await ChatGPTTokenStore.shared.signOut()
        append("signed out; revocation confirmed: \(revoked)")
    }

    private static let sampleImageBase64: String = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return image.jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
    }()
}
#endif
