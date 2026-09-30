import Foundation

protocol ClaudeServicing {
    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse
    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error>
}

extension ClaudeServicing {
    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        let response = try await send(request, credential: credential)
        return AsyncThrowingStream { continuation in
            continuation.yield(.messageStart)
            for (index, block) in response.content.enumerated() {
                switch block {
                case .text(let text):
                    continuation.yield(.contentBlockStart(index: index, kind: .text))
                    if !text.isEmpty {
                        continuation.yield(.textDelta(index: index, text))
                    }
                    continuation.yield(.contentBlockStop(index: index))
                case let .toolUse(id, name, input):
                    continuation.yield(.contentBlockStart(index: index, kind: .toolUse(id: id, name: name)))
                    if let json = String(data: (try? JSONEncoder().encode(input)) ?? Data(), encoding: .utf8), !json.isEmpty {
                        continuation.yield(.inputJSONDelta(index: index, json))
                    }
                    continuation.yield(.contentBlockStop(index: index))
                case .image, .toolResult, .passthrough:
                    if let raw = try? JSONEncoder().encode(block),
                       let value = try? JSONDecoder().decode(JSONValue.self, from: raw) {
                        continuation.yield(.passthroughBlock(index: index, value))
                    }
                }
            }
            continuation.yield(.messageDelta(stopReason: response.stopReason))
            continuation.yield(.messageStop)
            continuation.finish()
        }
    }
}

enum CoachChatConfig {
    static let defaultModel = "claude-sonnet-5"
    static let defaultOpenAIModel = "gpt-5-nano"
    static let anthropicVersion = "2023-06-01"
    static let historyLimit = 20
    static let maxToolRounds = 5
    /// Headroom for adaptive thinking plus a structured plan-edit tool call.
    /// Too low and the model stops mid-`tool_use`, truncating the reply and
    /// surfacing a spurious failure on plan-adjustment turns.
    static let maxOutputTokens = 16_384
}

enum ClaudeClientError: LocalizedError, Equatable {
    case badKey, rateLimited, offline, connectionLost, timedOut, invalidResponse, api(String)
    /// ChatGPT plan usage limit reached (`subscription_sharing_usage_limit_exceeded`).
    case planUsageLimit
    /// ChatGPT plan usage is unavailable for this account (`subscription_sharing_user_not_eligible`).
    case planNotEligible
    /// The ChatGPT session ended and the user has to sign in again.
    case needsReconnect
    /// The ChatGPT route rejected part of the request (`subscription_sharing_unsupported_capability`).
    case unsupportedCapability(param: String?)

    var errorDescription: String? {
        switch self {
        case .badKey: "Your Anthropic API key was rejected. Check it in Settings."
        case .rateLimited: "The coach provider is rate limited right now. Try again shortly."
        case .offline: "No network connection. Your chat history is safe."
        case .connectionLost: "Connection to the coach provider dropped mid-reply. Try again; your chat history is safe."
        case .timedOut: "The coach provider did not respond in time. A large plan edit can exceed the limit; try one change at a time."
        case .invalidResponse: "The coach provider returned an unexpected response."
        case .api(let message): message
        case .planUsageLimit: "ChatGPT reports a usage limit (subscription_sharing_usage_limit_exceeded). It can be your plan's limit or the limit set for TrainOrRest."
        case .planNotEligible: "ChatGPT plan use isn't available for this account. Add a Claude or OpenAI key in Settings."
        case .needsReconnect: "Your ChatGPT session ended. Reconnect ChatGPT in Settings; your chats are safe."
        case .unsupportedCapability(let param):
            "ChatGPT rejected part of the coach request\(param.map { " (\($0))" } ?? "")."
        }
    }
}

extension CoachCredential {
    /// The API key for key-based clients; ChatGPT tokens are not API keys.
    func requireAPIKey() throws -> String {
        guard case .apiKey(let key) = self else { throw ClaudeClientError.badKey }
        return key
    }
}

struct ClaudeRequest: Encodable {
    var model: String
    var maxTokens: Int = CoachChatConfig.maxOutputTokens
    var system: String
    var tools: [ClaudeTool]
    var toolChoice: CoachToolCatalog.ToolChoice? = nil
    var messages: [ClaudeMessageParam]

    enum CodingKeys: String, CodingKey {
        case model, system, tools, messages
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }
}

struct ClaudeMessageParam: Codable, Equatable {
    var role: String
    var content: [ClaudeContentBlock]
}

struct ClaudeTool: Encodable {
    var name: String
    var description: String
    var inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct ClaudeResponse: Decodable, Equatable {
    var content: [ClaudeContentBlock]
    var stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

final class ClaudeClient: ClaudeServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        let apiKey = try credential.requireAPIKey()
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(CoachChatConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                return try JSONDecoder().decode(ClaudeResponse.self, from: data)
            case 401, 403:
                throw ClaudeClientError.badKey
            case 429:
                throw ClaudeClientError.rateLimited
            default:
                throw ClaudeClientError.api(Self.errorMessage(from: data) ?? "Claude API error \(http.statusCode).")
            }
        } catch let error as ClaudeClientError {
            throw error
        } catch let error as URLError {
            throw Self.clientError(for: error)
        }
    }

    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        let urlRequest = try makeStreamingRequest(request, apiKey: credential.requireAPIKey())

        return AsyncThrowingStream { continuation in
            let task = Task {
                var attempt = 0
                var yieldedContent = false
                let maxAttempts = 2

                while !Task.isCancelled {
                    attempt += 1
                    do {
                        let didYieldContent = try await streamOnce(
                            urlRequest,
                            continuation: continuation
                        )
                        yieldedContent = yieldedContent || didYieldContent
                        continuation.finish()
                        return
                    } catch let error as ClaudeClientError {
                        continuation.finish(throwing: error)
                        return
                    } catch let error as URLError {
                        let mapped = Self.clientError(for: error)
                        if mapped == .connectionLost, !yieldedContent, attempt < maxAttempts {
                            continue
                        }
                        continuation.finish(throwing: mapped)
                        return
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeStreamingRequest(_ request: ClaudeRequest, apiKey: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(CoachChatConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.timeoutInterval = 120
        urlRequest.httpBody = try JSONEncoder().encode(StreamingClaudeRequest(request: request))
        return urlRequest
    }

    private func streamOnce(
        _ urlRequest: URLRequest,
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws -> Bool {
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw ClaudeClientError.badKey
        case 429:
            throw ClaudeClientError.rateLimited
        default:
            throw ClaudeClientError.api("Claude API error \(http.statusCode).")
        }

        var didYieldContent = false
        var parser = AnthropicSSEParser()
        for try await line in bytes.lines {
            for event in parser.feed(line + "\n") {
                if event.isResponseContent { didYieldContent = true }
                continuation.yield(event)
            }
        }
        for event in parser.finish() {
            if event.isResponseContent { didYieldContent = true }
            continuation.yield(event)
        }
        return didYieldContent
    }

    private static func clientError(for error: URLError) -> ClaudeClientError {
        switch error.code {
        case .notConnectedToInternet:
            return .offline
        case .timedOut:
            return .timedOut
        case .networkConnectionLost:
            return .connectionLost
        default:
            return .api(error.localizedDescription)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        return message
    }
}

private extension AnthropicStreamEvent {
    var isResponseContent: Bool {
        switch self {
        case .contentBlockStart, .textDelta, .inputJSONDelta, .contentBlockStop, .passthroughBlock:
            return true
        case .messageStart, .messageDelta, .messageStop, .ping, .error:
            return false
        }
    }
}

private struct StreamingClaudeRequest: Encodable {
    var model: String
    var maxTokens: Int
    var system: String
    var tools: [ClaudeTool]
    var toolChoice: CoachToolCatalog.ToolChoice?
    var messages: [ClaudeMessageParam]
    var stream = true

    enum CodingKeys: String, CodingKey {
        case model, system, tools, messages, stream
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
    }

    init(request: ClaudeRequest) {
        model = request.model
        maxTokens = request.maxTokens
        system = request.system
        tools = request.tools
        toolChoice = request.toolChoice
        messages = request.messages
    }
}
