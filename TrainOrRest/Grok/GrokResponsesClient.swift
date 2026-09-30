import Foundation

final class GrokResponsesClient: ClaudeServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        let stream = try await stream(request, credential: credential)
        var collector = GrokResponseCollector()
        for try await event in stream {
            try collector.ingest(event)
        }
        return try collector.response()
    }

    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        guard case .grok(let provider) = credential else {
            throw ClaudeClientError.api("Your Grok session ended. Sign in again in Settings; your chats are safe.")
        }
        var resolved = request
        if resolved.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved.model = GrokAuthConfiguration.defaultModel
        }
        let body = try GrokResponsesEncoding.body(for: resolved)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var token = try await provider.accessToken()
                    var refreshed = false
                    var retriedConnectionLoss = false
                    while !Task.isCancelled {
                        do {
                            try await self.streamOnce(body: body, token: token, continuation: continuation)
                            continuation.finish()
                            return
                        } catch is GrokUnauthorized {
                            if refreshed {
                                continuation.finish(throwing: ClaudeClientError.api("Your Grok session ended. Sign in again in Settings; your chats are safe."))
                                return
                            }
                            refreshed = true
                            token = try await provider.refreshAfterUnauthorized()
                        } catch let error as ClaudeClientError {
                            if error == .connectionLost, !retriedConnectionLoss {
                                retriedConnectionLoss = true
                                continue
                            }
                            continuation.finish(throwing: error)
                            return
                        } catch let error as URLError {
                            let mapped = Self.clientError(for: error)
                            if mapped == .connectionLost, !retriedConnectionLoss {
                                retriedConnectionLoss = true
                                continue
                            }
                            continuation.finish(throwing: mapped)
                            return
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamOnce(
        body: Data,
        token: String,
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: GrokAuthConfiguration.responsesURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.invalidResponse }
        if http.statusCode == 401 { throw GrokUnauthorized() }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.error(for: http.statusCode, data: data)
        }

        var parser = ResponsesSSEParser()
        var translator = GrokStreamTranslator()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            for message in parser.feed(line + "\n") {
                for event in try translator.translate(message) {
                    continuation.yield(event)
                }
            }
        }
        for message in parser.finish() {
            for event in try translator.translate(message) {
                continuation.yield(event)
            }
        }
        if !translator.completed {
            throw ClaudeClientError.connectionLost
        }
    }

    private static func error(for status: Int, data: Data) -> ClaudeClientError {
        if status == 429 || status == 503 { return .rateLimited }
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { payload -> String? in
                if let error = payload["error"] as? [String: Any], let message = error["message"] as? String {
                    return message
                }
                return payload["error"] as? String
            }
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = (trimmed?.isEmpty == false ? trimmed : nil).map { String($0.prefix(240)) }
        return .api(safe ?? "Grok error \(status).")
    }

    private static func clientError(for error: URLError) -> ClaudeClientError {
        switch error.code {
        case .notConnectedToInternet: .offline
        case .timedOut: .timedOut
        case .networkConnectionLost: .connectionLost
        default: .api(error.localizedDescription)
        }
    }
}

private struct GrokUnauthorized: Error {}

enum GrokResponsesEncoding {
    static func body(for request: ClaudeRequest) throws -> Data {
        try JSONEncoder().encode(GrokResponsesRequest(from: request))
    }
}

struct GrokResponsesRequest: Encodable {
    var model: String
    var instructions: String
    var input: [GrokInputItem]
    var tools: [GrokFunctionTool]?
    var toolChoice: GrokToolChoice?
    var store = false
    var stream = true

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, tools, store, stream
        case toolChoice = "tool_choice"
    }

    init(from request: ClaudeRequest) {
        model = request.model
        instructions = request.system
        input = request.messages.flatMap(GrokInputItem.items)
        guard !request.tools.isEmpty else {
            tools = nil
            toolChoice = nil
            return
        }
        tools = request.tools.map(GrokFunctionTool.init)
        toolChoice = GrokToolChoice(from: request.toolChoice)
    }
}

struct GrokFunctionTool: Encodable {
    var type = "function"
    var name: String
    var description: String
    var parameters: JSONValue

    init(_ tool: ClaudeTool) {
        name = tool.name
        description = tool.description
        parameters = tool.inputSchema
    }
}

enum GrokToolChoice: Encodable {
    case mode(String)
    case function(String)

    init?(from choice: CoachToolCatalog.ToolChoice?) {
        guard let choice else { return nil }
        switch choice {
        case .auto: self = .mode("auto")
        case .any: self = .mode("required")
        case .tool(let name): self = .function(name)
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
            try container.encode(name, forKey: .name)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, name
    }
}

enum GrokInputItem: Encodable {
    case message(role: String, content: [GrokMessageContent])
    case functionCall(callID: String, name: String, arguments: String)
    case functionCallOutput(callID: String, output: String)

    private enum CodingKeys: String, CodingKey {
        case type, role, content, name, arguments, output
        case callID = "call_id"
    }

    static func items(from message: ClaudeMessageParam) -> [GrokInputItem] {
        let textRole = message.role == "assistant" ? "assistant" : "user"
        var items: [GrokInputItem] = []
        var activeRole: String?
        var activeContent: [GrokMessageContent] = []

        func flush() {
            guard let role = activeRole else { return }
            items.append(.message(role: role, content: activeContent))
            activeContent.removeAll(keepingCapacity: true)
            activeRole = nil
        }

        for block in message.content {
            switch block {
            case .text(let text):
                if activeRole != textRole {
                    flush()
                    activeRole = textRole
                }
                activeContent.append(.text(text, role: textRole))
            case .image(let mediaType, let data):
                if activeRole != "user" {
                    flush()
                    activeRole = "user"
                }
                activeContent.append(.image(mediaType: mediaType, data: data))
            case .toolUse(let id, let name, let input):
                flush()
                items.append(.functionCall(callID: id, name: name, arguments: json(input)))
            case .toolResult(let toolUseID, let content, let isError):
                flush()
                items.append(.functionCallOutput(callID: toolUseID, output: isError ? "ERROR: \(content)" : content))
            case .passthrough:
                continue
            }
        }
        flush()
        return items
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let role, let content):
            try container.encode("message", forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
        case .functionCall(let callID, let name, let arguments):
            try container.encode("function_call", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case .functionCallOutput(let callID, let output):
            try container.encode("function_call_output", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(output, forKey: .output)
        }
    }

    private static func json(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

enum GrokMessageContent: Encodable {
    case text(String, role: String)
    case image(mediaType: String, data: String)

    private enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text, let role):
            try container.encode(role == "assistant" ? "output_text" : "input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let data):
            try container.encode("input_image", forKey: .type)
            try container.encode("data:\(mediaType);base64,\(data)", forKey: .imageURL)
        }
    }
}

struct GrokStreamTranslator {
    private(set) var completed = false
    private var started: Set<Int> = []
    private var sawArguments: Set<Int> = []
    private var sawFunctionCall = false

    mutating func translate(_ message: ResponsesSSEParser.Message) throws -> [AnthropicStreamEvent] {
        guard let payload = try? JSONDecoder().decode(GrokStreamPayload.self, from: Data(message.data.utf8)) else {
            throw ClaudeClientError.invalidResponse
        }
        guard let type = message.event ?? payload.type else { return [] }
        switch type {
        case "response.created":
            return [.messageStart]
        case "response.output_item.added":
            guard let index = payload.outputIndex, let item = payload.item else {
                throw ClaudeClientError.invalidResponse
            }
            switch item.type {
            case "message":
                started.insert(index)
                return [.contentBlockStart(index: index, kind: .text)]
            case "function_call":
                guard let callID = item.callID, let name = item.name else {
                    throw ClaudeClientError.invalidResponse
                }
                started.insert(index)
                sawFunctionCall = true
                return [.contentBlockStart(index: index, kind: .toolUse(id: callID, name: name))]
            default:
                return []
            }
        case "response.output_text.delta":
            guard let index = payload.outputIndex, started.contains(index) else { return [] }
            return [.textDelta(index: index, payload.delta ?? "")]
        case "response.function_call_arguments.delta":
            guard let index = payload.outputIndex, started.contains(index) else { return [] }
            sawArguments.insert(index)
            return [.inputJSONDelta(index: index, payload.delta ?? "")]
        case "response.output_item.done":
            guard let index = payload.outputIndex, let item = payload.item, started.contains(index) else {
                return []
            }
            started.remove(index)
            guard item.type == "message" || item.type == "function_call" else { return [] }
            if item.type == "function_call", !sawArguments.contains(index), let arguments = item.arguments {
                return [.inputJSONDelta(index: index, arguments), .contentBlockStop(index: index)]
            }
            return [.contentBlockStop(index: index)]
        case "response.completed":
            completed = true
            return [.messageDelta(stopReason: sawFunctionCall ? "tool_use" : "end_turn"), .messageStop]
        case "response.incomplete":
            throw ClaudeClientError.api("Grok stopped early: \(payload.response?.incompleteDetails?.reason ?? "unknown").")
        case "response.failed", "error":
            throw ClaudeClientError.api(payload.failureMessage)
        default:
            return []
        }
    }
}

private struct GrokStreamPayload: Decodable {
    var type: String?
    var outputIndex: Int?
    var delta: String?
    var item: Item?
    var response: Response?
    var message: String?

    struct Item: Decodable {
        var type: String
        var callID: String?
        var name: String?
        var arguments: String?

        enum CodingKeys: String, CodingKey {
            case type, name, arguments
            case callID = "call_id"
        }
    }

    struct Response: Decodable {
        var incompleteDetails: Incomplete?
        var error: APIError?

        enum CodingKeys: String, CodingKey {
            case error
            case incompleteDetails = "incomplete_details"
        }
    }

    struct Incomplete: Decodable { var reason: String? }
    struct APIError: Decodable { var message: String? }

    enum CodingKeys: String, CodingKey {
        case type, delta, item, response, message
        case outputIndex = "output_index"
    }

    var failureMessage: String {
        let text = response?.error?.message ?? message
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed : nil).map { String($0.prefix(240)) } ?? "Grok stream error."
    }
}

private struct GrokResponseCollector {
    private enum Block {
        case text(String)
        case tool(id: String, name: String, arguments: String)
    }

    private var active: [Int: Block] = [:]
    private var completed: [Int: ClaudeContentBlock] = [:]
    private var stopReason: String?

    mutating func ingest(_ event: AnthropicStreamEvent) throws {
        switch event {
        case .messageStart:
            active.removeAll()
            completed.removeAll()
            stopReason = nil
        case .contentBlockStart(let index, let kind):
            switch kind {
            case .text: active[index] = .text("")
            case .toolUse(let id, let name): active[index] = .tool(id: id, name: name, arguments: "")
            }
        case .textDelta(let index, let delta):
            guard case .text(let text)? = active[index] else { return }
            active[index] = .text(text + delta)
        case .inputJSONDelta(let index, let delta):
            guard case .tool(let id, let name, let arguments)? = active[index] else { return }
            active[index] = .tool(id: id, name: name, arguments: arguments + delta)
        case .contentBlockStop(let index):
            guard let block = active.removeValue(forKey: index) else { return }
            switch block {
            case .text(let text):
                completed[index] = .text(text)
            case .tool(let id, let name, let arguments):
                let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8))) ?? .object([:])
                completed[index] = .toolUse(id: id, name: name, input: input)
            }
        case .messageDelta(let reason):
            stopReason = reason
        case .messageStop, .passthroughBlock, .ping, .error:
            return
        }
    }

    func response() -> ClaudeResponse {
        ClaudeResponse(
            content: completed.keys.sorted().compactMap { completed[$0] },
            stopReason: stopReason
        )
    }
}
