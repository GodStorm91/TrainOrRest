import Foundation
import StoreKit

/// Token-free record of recent ChatGPT plan requests, kept to explain
/// server-reported limits: HTTP status, error body, response headers, request
/// shape, and token usage. Never stores tokens, prompts, or replies.
final class ChatGPTDiagnostics: @unchecked Sendable {
    static let shared = ChatGPTDiagnostics()

    /// Names the probe step that issued the current request.
    @TaskLocal static var label: String?

    struct Entry: Codable, Equatable, Sendable {
        var date: Date
        var endpoint: String
        var label: String?
        var model: String?
        var status: Int?
        var outcome: String
        var errorCode: String?
        var errorMessage: String?
        var errorParam: String?
        var body: String?
        var requestID: String?
        var headers: [String: String] = [:]
        var request: RequestShape?
        var usage: Usage?
        var note: String?
    }

    struct RequestShape: Codable, Equatable, Sendable {
        var bodyBytes: Int
        var instructionsCharacters: Int
        var inputItems: Int
        var images: Int
        var tools: Int
        var toolChoice: String?
    }

    struct Usage: Codable, Equatable, Sendable {
        var inputTokens: Int?
        var cachedInputTokens: Int?
        var outputTokens: Int?
        var reasoningTokens: Int?
    }

    private static let storageKey = "chatGPTDiagnostics.entries"
    private static let entryLimit = 40
    private static let bodyLimit = 2_000
    private static let headerValueLimit = 300

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var storedEntries: [Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedEntries = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries
    }

    func record(_ entry: Entry) {
        var entry = entry
        if entry.label == nil { entry.label = Self.label }
        lock.lock()
        storedEntries.append(entry)
        if storedEntries.count > Self.entryLimit {
            storedEntries.removeFirst(storedEntries.count - Self.entryLimit)
        }
        let snapshot = storedEntries
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func clear() {
        lock.lock()
        storedEntries.removeAll()
        lock.unlock()
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Response headers without cookies or credentials.
    static func headers(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            let name = String(describing: key).lowercased()
            guard !name.contains("cookie"), !name.contains("authorization"), !name.contains("token") else { continue }
            headers[name] = String(String(describing: value).prefix(headerValueLimit))
        }
        return headers
    }

    static func truncatedBody(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return String(String(decoding: data, as: UTF8.self).prefix(bodyLimit))
    }

    /// Diagnostics UI ships in DEBUG and TestFlight builds. The report holds no
    /// secrets, so an unverifiable App Store environment shows it too.
    static func isAvailableInThisBuild() async -> Bool {
        #if DEBUG
        return true
        #else
        guard let transaction = try? await AppTransaction.shared else { return true }
        return transaction.unsafePayloadValue.environment != .production
        #endif
    }

    func report(summary: [String]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines = summary
        lines.append("")
        for entry in entries.reversed() {
            var head = "[\(formatter.string(from: entry.date))] \(entry.endpoint) \(entry.outcome)"
            if let status = entry.status { head += " HTTP \(status)" }
            if let label = entry.label { head += " · \(label)" }
            lines.append(head)
            if let model = entry.model { lines.append("  model: \(model)") }
            if let code = entry.errorCode { lines.append("  error.code: \(code)") }
            if let message = entry.errorMessage { lines.append("  error.message: \(message)") }
            if let param = entry.errorParam { lines.append("  error.param: \(param)") }
            if let requestID = entry.requestID { lines.append("  x-request-id: \(requestID)") }
            if let note = entry.note { lines.append("  note: \(note)") }
            if let shape = entry.request {
                lines.append(
                    "  request: \(shape.bodyBytes) B, instructions \(shape.instructionsCharacters) chars, "
                        + "\(shape.inputItems) input items, \(shape.images) images, \(shape.tools) tools, "
                        + "tool_choice \(shape.toolChoice ?? "none")"
                )
            }
            if let usage = entry.usage {
                lines.append(
                    "  usage: input \(Self.describe(usage.inputTokens)) (cached \(Self.describe(usage.cachedInputTokens))), "
                        + "output \(Self.describe(usage.outputTokens)) (reasoning \(Self.describe(usage.reasoningTokens)))"
                )
            }
            if let body = entry.body { lines.append("  body: \(body)") }
            for key in entry.headers.keys.sorted() {
                lines.append("  < \(key): \(entry.headers[key] ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ value: Int?) -> String {
        value.map(String.init) ?? "?"
    }
}

extension ChatGPTDiagnostics {
    /// Claims of a JWT access token with identifying values replaced by `<present>`.
    static func redactedClaims(ofJWT token: String) -> [String] {
        let segments = token.split(separator: ".")
        guard segments.count >= 2, let payload = base64URLDecode(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return ["access token: not a JWT"]
        }
        var lines: [String] = []
        flatten(object, prefix: "", into: &lines)
        return lines.sorted()
    }

    private static func flatten(_ object: [String: Any], prefix: String, into lines: inout [String]) {
        for (key, value) in object {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nested = value as? [String: Any] {
                flatten(nested, prefix: path, into: &lines)
                continue
            }
            if isIdentifying(key) {
                lines.append("\(path): <present>")
                continue
            }
            if let array = value as? [Any] {
                lines.append("\(path): \(array.map { String(describing: $0) }.joined(separator: " "))")
            } else if let number = value as? NSNumber, ["exp", "iat", "nbf", "auth_time", "pwd_auth_time"].contains(key) {
                let date = Date(timeIntervalSince1970: number.doubleValue)
                lines.append("\(path): \(number) (\(ISO8601DateFormatter().string(from: date)))")
            } else {
                lines.append("\(path): \(String(describing: value).prefix(120))")
            }
        }
    }

    private static func isIdentifying(_ key: String) -> Bool {
        let key = key.lowercased()
        let markers = ["email", "sub", "user", "account", "name", "sid", "jti", "org", "session", "id"]
        guard key != "client_id" else { return false }
        return markers.contains { key == $0 || key.hasSuffix("_\($0)") || key.hasPrefix("\($0)_") }
            || key.hasSuffix("id")
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

/// Small requests that separate an account-wide limit from one tied to the
/// model, the request size, or tools. Each step lands in `ChatGPTDiagnostics`.
@MainActor
enum ChatGPTDiagnosticsProbe {
    static func run(selectedModel: String, tokenStore: ChatGPTTokenStore = .shared) async -> [String] {
        let info = Bundle.main.infoDictionary
        var summary = [
            "TrainOrRest \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "probe at \(ISO8601DateFormatter().string(from: Date()))",
            "state: \(stateName(tokenStore.state))",
            "selected model: \(selectedModel.isEmpty ? "(default)" : selectedModel)"
        ]

        do {
            let token = try await tokenStore.accessToken()
            summary += ChatGPTDiagnostics.redactedClaims(ofJWT: token).map { "claim \($0)" }
        } catch {
            summary.append("access token unavailable: \(String(describing: error))")
        }

        var listed: [ChatGPTModel] = []
        do {
            listed = try await ChatGPTDiagnostics.$label.withValue("probe models") {
                try await ChatGPTModelCatalog.shared.models(tokenProvider: tokenStore, forceRefresh: true)
            }
            summary.append("listed models: \(listed.map(\.id).joined(separator: ", "))")
        } catch {
            summary.append("models failed: \(String(describing: error))")
        }

        let primary = selectedModel.isEmpty ? (ChatGPTModelCatalog.defaultModel(from: listed) ?? "") : selectedModel
        var models = [primary]
        models += listed.map(\.id).filter { $0 != primary }.prefix(2)
        let client = ChatGPTResponsesClient()
        for model in models where !model.isEmpty {
            let outcome = await send(client, model: model, withTools: false, label: "probe tiny \(model)")
            summary.append("tiny \(model): \(outcome)")
        }
        if !primary.isEmpty {
            let outcome = await send(client, model: primary, withTools: true, label: "probe tools \(primary)")
            summary.append("tools \(primary): \(outcome)")
        }
        summary.append("state after probe: \(stateName(tokenStore.state))")
        return summary
    }

    private static func send(_ client: ChatGPTResponsesClient, model: String, withTools: Bool, label: String) async -> String {
        let request = ClaudeRequest(
            model: model,
            system: withTools ? "Reply by calling the coach_response tool with a one-word answer." : "Reply with a short health check.",
            tools: withTools ? [CoachToolCatalog.coachResponse] : [],
            toolChoice: withTools ? .tool(name: CoachToolCatalog.coachResponseName) : nil,
            messages: [ClaudeMessageParam(role: "user", content: [.text("Say OK.")])]
        )
        do {
            _ = try await ChatGPTDiagnostics.$label.withValue(label) {
                try await client.send(request, credential: .chatGPT(ChatGPTTokenStore.shared))
            }
            return "ok"
        } catch {
            return "failed \(String(describing: error))"
        }
    }

    private static func stateName(_ state: ChatGPTConnectionState) -> String {
        switch state {
        case .signedOut: "signedOut"
        case .connected: "connected"
        case .planUsageDisabled: "planUsageDisabled"
        case .needsReconnect: "needsReconnect"
        case .usageLimited(let until): "usageLimited(until: \(until.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"))"
        case .notEligible: "notEligible"
        }
    }
}
