import Foundation

final class OpenAIClient: ClaudeServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        let apiKey = try credential.requireAPIKey()
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.timeoutInterval = 120
        urlRequest.httpBody = try JSONEncoder().encode(OpenAIChatRequest(from: request))

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
                return try decoded.asClaudeResponse
            case 401, 403:
                throw ClaudeClientError.api("Your OpenAI API key was rejected. Check it in Settings.")
            case 429:
                throw ClaudeClientError.rateLimited
            default:
                throw ClaudeClientError.api(Self.errorMessage(from: data) ?? "OpenAI API error \(http.statusCode).")
            }
        } catch let error as ClaudeClientError {
            throw error
        } catch let error as URLError {
            throw Self.clientError(for: error)
        }
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

private struct OpenAIChatRequest: Encodable {
    var model: String
    var messages: [OpenAIMessage]
    var tools: [OpenAITool]?
    var toolChoice: OpenAIToolChoice?
    var maxCompletionTokens: Int
    var reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools
        case toolChoice = "tool_choice"
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
    }

    init(from request: ClaudeRequest) {
        model = request.model
        maxCompletionTokens = request.maxTokens
        reasoningEffort = request.model.hasPrefix("gpt-5") ? "minimal" : nil
        messages = [.init(role: "system", content: .text(request.system))]
        messages += request.messages.flatMap(OpenAIMessage.messages(from:))
        if request.tools.isEmpty {
            tools = nil
            toolChoice = nil
        } else {
            tools = request.tools.map(OpenAITool.init(from:))
            toolChoice = OpenAIToolChoice(from: request.toolChoice)
        }
    }
}

private enum OpenAIToolChoice: Encodable {
    case mode(String)
    case function(name: String)

    private enum CodingKeys: String, CodingKey {
        case type, function
    }

    private enum FunctionCodingKeys: String, CodingKey {
        case name
    }

    init(from toolChoice: CoachToolCatalog.ToolChoice?) {
        switch toolChoice {
        case .auto, .none:
            self = .mode("auto")
        case .any:
            self = .mode("required")
        case .tool(let name):
            self = .function(name: name)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .mode(let mode):
            var container = encoder.singleValueContainer()
            try container.encode(mode)
        case .function(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("function", forKey: .type)
            var function = container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
            try function.encode(name, forKey: .name)
        }
    }
}

private struct OpenAIMessage: Codable {
    var role: String
    var content: OpenAIMessageContent?
    var toolCallID: String?
    var toolCalls: [OpenAIToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    static func messages(from message: ClaudeMessageParam) -> [OpenAIMessage] {
        let text = message.content.textContent
        let toolUses = message.content.compactMap { block -> OpenAIToolCall? in
            guard case let .toolUse(id, name, input) = block else { return nil }
            return OpenAIToolCall(id: id, type: "function", function: .init(name: name, arguments: input.jsonString))
        }
        let toolResults = message.content.compactMap { block -> OpenAIMessage? in
            guard case let .toolResult(toolUseID, content, isError) = block else { return nil }
            let prefix = isError ? "Error: " : ""
            return OpenAIMessage(role: "tool", content: .text(prefix + content), toolCallID: toolUseID, toolCalls: nil)
        }
        if !toolResults.isEmpty { return toolResults }

        let openAIRole = message.role == "assistant" ? "assistant" : "user"
        if !toolUses.isEmpty {
            return [OpenAIMessage(role: "assistant", content: text.isEmpty ? nil : .text(text), toolCallID: nil, toolCalls: toolUses)]
        }
        let parts = message.content.openAIParts(fallbackText: text)
        let content: OpenAIMessageContent = parts.contains { $0.imageURL != nil } ? .parts(parts) : .text(text)
        return [OpenAIMessage(role: openAIRole, content: content, toolCallID: nil, toolCalls: nil)]
    }
}

private enum OpenAIMessageContent: Codable {
    case text(String)
    case parts([OpenAIContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .parts(try container.decode([OpenAIContentPart].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

private struct OpenAIContentPart: Codable {
    var type: String
    var text: String?
    var imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    struct ImageURL: Codable {
        var url: String
    }
}

private struct OpenAITool: Encodable {
    var type = "function"
    var function: Function

    struct Function: Encodable {
        var name: String
        var description: String
        var parameters: JSONValue
    }

    init(from tool: ClaudeTool) {
        function = Function(name: tool.name, description: tool.description, parameters: tool.inputSchema)
    }
}

private struct OpenAIToolCall: Codable {
    var id: String
    var type: String
    var function: Function

    struct Function: Codable {
        var name: String
        var arguments: String
    }
}

private struct OpenAIChatResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        var content: String?
        var toolCalls: [OpenAIToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    var asClaudeResponse: ClaudeResponse {
        get throws {
            guard let choice = choices.first else {
                throw ClaudeClientError.invalidResponse
            }
            var content: [ClaudeContentBlock] = []
            if let text = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                content.append(.text(text))
            }
            for call in choice.message.toolCalls ?? [] {
                content.append(.toolUse(
                    id: call.id,
                    name: call.function.name,
                    input: JSONValue(jsonString: call.function.arguments) ?? .object([:])
                ))
            }
            guard !content.isEmpty else {
                if choice.finishReason == "length" {
                    throw ClaudeClientError.api("OpenAI stopped before returning an answer. Try again or switch to a larger OpenAI model in Settings.")
                }
                throw ClaudeClientError.invalidResponse
            }
            return ClaudeResponse(content: content, stopReason: choice.finishReason == "tool_calls" ? nil : choice.finishReason)
        }
    }
}

private extension Array where Element == ClaudeContentBlock {
    func openAIParts(fallbackText: String) -> [OpenAIContentPart] {
        var parts: [OpenAIContentPart] = []
        if !fallbackText.isEmpty {
            parts.append(OpenAIContentPart(type: "text", text: fallbackText, imageURL: nil))
        }
        for block in self {
            if case let .image(mediaType, data) = block {
                parts.append(OpenAIContentPart(
                    type: "image_url",
                    text: nil,
                    imageURL: .init(url: "data:\(mediaType);base64,\(data)")
                ))
            }
        }
        if parts.isEmpty {
            parts.append(OpenAIContentPart(type: "text", text: "", imageURL: nil))
        }
        return parts
    }
}

private extension JSONValue {
    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        self = value
    }

    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
