import Foundation

protocol ClaudeServicing {
    func send(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse
    func stream(_ request: ClaudeRequest, apiKey: String) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error>
}

extension ClaudeServicing {
    func stream(_ request: ClaudeRequest, apiKey: String) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        let response = try await send(request, apiKey: apiKey)
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
    static let anthropicVersion = "2023-06-01"
    static let historyLimit = 20
    static let maxToolRounds = 3
    /// Headroom for adaptive thinking plus a structured tool call. Too low and
    /// the model stops mid-`tool_use`, leaving an input we must never execute.
    static let maxOutputTokens = 4_096
}

enum ClaudeClientError: LocalizedError {
    case badKey, rateLimited, offline, invalidResponse, api(String)

    var errorDescription: String? {
        switch self {
        case .badKey: "Your Anthropic API key was rejected. Check it in Settings."
        case .rateLimited: "Claude is rate limited right now. Try again shortly."
        case .offline: "No network connection. Your chat history is safe."
        case .invalidResponse: "Claude returned an unexpected response."
        case .api(let message): message
        }
    }
}

struct ClaudeRequest: Encodable {
    var model: String
    var maxTokens: Int = CoachChatConfig.maxOutputTokens
    var system: String
    var tools: [ClaudeTool]
    var messages: [ClaudeMessageParam]

    enum CodingKeys: String, CodingKey {
        case model, system, tools, messages
        case maxTokens = "max_tokens"
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

    func send(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse {
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
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ClaudeClientError.offline
        }
    }

    func stream(_ request: ClaudeRequest, apiKey: String) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(CoachChatConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(StreamingClaudeRequest(request: request))

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
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

                    var parser = AnthropicSSEParser()
                    for try await line in bytes.lines {
                        for event in parser.feed(line + "\n") {
                            continuation.yield(event)
                        }
                    }
                    for event in parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch let error as ClaudeClientError {
                    continuation.finish(throwing: error)
                } catch let error as URLError where error.code == .notConnectedToInternet {
                    continuation.finish(throwing: ClaudeClientError.offline)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        return message
    }
}

private struct StreamingClaudeRequest: Encodable {
    var model: String
    var maxTokens: Int
    var system: String
    var tools: [ClaudeTool]
    var messages: [ClaudeMessageParam]
    var stream = true

    enum CodingKeys: String, CodingKey {
        case model, system, tools, messages, stream
        case maxTokens = "max_tokens"
    }

    init(request: ClaudeRequest) {
        model = request.model
        maxTokens = request.maxTokens
        system = request.system
        tools = request.tools
        messages = request.messages
    }
}
