import Foundation
import os

final class ChatGPTResponsesClient: ClaudeServicing {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.trainorrest.app",
        category: "ChatGPTResponses"
    )

    private let session: URLSession
    private let catalog: ChatGPTModelCatalog

    init(session: URLSession = .shared, catalog: ChatGPTModelCatalog = .shared) {
        self.session = session
        self.catalog = catalog
    }

    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        let stream = try await stream(request, credential: credential)
        var collector = ResponsesResponseCollector()
        for try await event in stream {
            try collector.ingest(event)
        }
        return try collector.response()
    }

    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        guard case .chatGPT(let provider) = credential else {
            throw ClaudeClientError.needsReconnect
        }

        var resolvedRequest = request
        if resolvedRequest.model.isEmpty {
            resolvedRequest.model = try await catalog.resolveSelectedModel(tokenProvider: provider)
        }
        let requestBody = try JSONEncoder().encode(ResponsesRequest(from: resolvedRequest))

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var token = try await provider.accessToken()
                    var didRefreshAfterUnauthorized = false
                    var retriedConnectionLoss = false

                    while !Task.isCancelled {
                        do {
                            _ = try await self.streamOnce(
                                body: requestBody,
                                token: token,
                                continuation: continuation
                            )
                            continuation.finish()
                            return
                        } catch let failure as ChatGPTStreamAttemptFailure {
                            let error = failure.error
                            if Self.recordsPlanError(error) {
                                await provider.recordPlanError(error)
                            }
                            if error == .connectionLost, !failure.didYieldContent, !retriedConnectionLoss {
                                retriedConnectionLoss = true
                                continue
                            }
                            continuation.finish(throwing: error)
                            return
                        } catch is ChatGPTUnauthorizedResponse {
                            if !didRefreshAfterUnauthorized {
                                didRefreshAfterUnauthorized = true
                                token = try await provider.refreshAfterUnauthorized()
                                continue
                            }

                            let error = ClaudeClientError.needsReconnect
                            await provider.recordPlanError(error)
                            continuation.finish(throwing: error)
                            return
                        } catch let error as ClaudeClientError {
                            if Self.recordsPlanError(error) {
                                await provider.recordPlanError(error)
                            }
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
                } catch let error as ClaudeClientError {
                    if Self.recordsPlanError(error) {
                        await provider.recordPlanError(error)
                    }
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: Self.clientError(for: error))
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
    ) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        request.httpBody = body

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeClientError.invalidResponse
        }
        let requestID = http.value(forHTTPHeaderField: "x-request-id")

        guard (200..<300).contains(http.statusCode) else {
            var responseData = Data()
            for try await byte in bytes {
                responseData.append(byte)
            }
            Self.logRequestID(requestID)
            if http.statusCode == 401 {
                throw ChatGPTUnauthorizedResponse()
            }
            throw Self.error(for: http.statusCode, data: responseData)
        }

        var parser = ResponsesSSEParser()
        var translator = ResponsesStreamTranslator()
        var didYieldContent = false

        do {
            for try await line in bytes.lines {
                for message in parser.feed(line + "\n") {
                    let events = try translator.translate(message)
                    for event in events {
                        if event.isResponseContent {
                            didYieldContent = true
                        }
                        continuation.yield(event)
                    }
                }
            }
            for message in parser.finish() {
                let events = try translator.translate(message)
                for event in events {
                    if event.isResponseContent {
                        didYieldContent = true
                    }
                    continuation.yield(event)
                }
            }
            guard translator.completed else {
                throw ClaudeClientError.connectionLost
            }
            return didYieldContent
        } catch let error as ClaudeClientError {
            Self.logRequestID(requestID)
            throw ChatGPTStreamAttemptFailure(error: error, didYieldContent: didYieldContent)
        } catch let error as URLError {
            Self.logRequestID(requestID)
            throw ChatGPTStreamAttemptFailure(
                error: Self.clientError(for: error),
                didYieldContent: didYieldContent
            )
        } catch {
            Self.logRequestID(requestID)
            throw error
        }
    }

    private static func recordsPlanError(_ error: ClaudeClientError) -> Bool {
        switch error {
        case .planUsageLimit, .planNotEligible, .needsReconnect:
            true
        default:
            false
        }
    }

    private struct ChatGPTStreamAttemptFailure: Error {
        var error: ClaudeClientError
        var didYieldContent: Bool
    }

    private static func clientError(for error: URLError) -> ClaudeClientError {
        switch error.code {
        case .notConnectedToInternet:
            .offline
        case .timedOut:
            .timedOut
        case .networkConnectionLost:
            .connectionLost
        default:
            .api(error.localizedDescription)
        }
    }

    private static func error(for status: Int, data: Data) -> ClaudeClientError {
        let body = try? JSONDecoder().decode(ChatGPTErrorBody.self, from: data)
        return mapError(
            body?.error,
            status: status,
            detail: body?.detail,
            fallback: "ChatGPT error \(status)."
        )
    }

    fileprivate static func mapError(
        _ error: ChatGPTAPIError?,
        status: Int?,
        detail: String? = nil,
        fallback: String
    ) -> ClaudeClientError {
        switch error?.code {
        case "subscription_sharing_usage_limit_exceeded":
            return .planUsageLimit
        case "subscription_sharing_user_not_eligible":
            return .planNotEligible
        case "subscription_sharing_invalid_user":
            return .needsReconnect
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            return .rateLimited
        case "subscription_sharing_unsupported_capability":
            return .unsupportedCapability(param: error?.param)
        default:
            break
        }

        if let detail {
            return .api(detail)
        }
        if status == 503 || status == 429 {
            return .rateLimited
        }
        if status == 403 {
            return .api(error?.message ?? "ChatGPT refused the request (403).")
        }
        return .api(error?.message ?? fallback)
    }

    private static func logRequestID(_ requestID: String?) {
        guard let requestID, !requestID.isEmpty else { return }
        logger.debug("ChatGPT Responses request failed (x-request-id: \(requestID, privacy: .public)).")
    }
}

private struct ChatGPTUnauthorizedResponse: Error {}

private struct ResponsesRequest: Encodable {
    var model: String
    var instructions: String
    var input: [ResponsesInputItem]
    var tools: [ResponsesToolNamespace]?
    var toolChoice: ResponsesToolChoice?
    var store = false
    var stream = true

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, tools, store, stream
        case toolChoice = "tool_choice"
    }

    init(from request: ClaudeRequest) {
        model = request.model
        instructions = request.system
        input = request.messages.flatMap(ResponsesInputItem.items)

        guard !request.tools.isEmpty else {
            tools = nil
            toolChoice = nil
            return
        }

        let selectedTools = Self.selectedTools(from: request)
        tools = [ResponsesToolNamespace(tools: selectedTools)]
        toolChoice = ResponsesToolChoice(from: request.toolChoice)
    }

    private static func selectedTools(from request: ClaudeRequest) -> [ClaudeTool] {
        guard case .tool(let name) = request.toolChoice else {
            return request.tools
        }
        // Namespaces accept a plain required choice. Restricting the namespace
        // keeps a forced call unambiguous without relying on an unverified form.
        return request.tools.filter { $0.name == name }
    }
}

private enum ResponsesInputItem: Encodable {
    case message(role: String, content: [ResponsesMessageContent])
    case functionCall(callID: String, name: String, arguments: String)
    case functionCallOutput(callID: String, output: String)

    private enum CodingKeys: String, CodingKey {
        case type, role, content, name, arguments, output
        case callID = "call_id"
    }

    static func items(from message: ClaudeMessageParam) -> [ResponsesInputItem] {
        let textRole = message.role == "assistant" ? "assistant" : "user"
        var items: [ResponsesInputItem] = []
        var activeRole: String?
        var activeContent: [ResponsesMessageContent] = []

        func appendMessageContent(_ content: ResponsesMessageContent, role: String) {
            if activeRole != role {
                if let activeRole {
                    items.append(.message(role: activeRole, content: activeContent))
                    activeContent.removeAll(keepingCapacity: true)
                }
                activeRole = role
            }
            activeContent.append(content)
        }

        func flushActiveMessage() {
            guard let role = activeRole else { return }
            items.append(.message(role: role, content: activeContent))
            activeContent.removeAll(keepingCapacity: true)
            activeRole = nil
        }

        for block in message.content {
            switch block {
            case .text(let text):
                appendMessageContent(.text(text, role: textRole), role: textRole)
            case .image(let mediaType, let data):
                appendMessageContent(.image(mediaType: mediaType, data: data), role: "user")
            case .toolUse(let id, let name, let input):
                flushActiveMessage()
                items.append(.functionCall(callID: id, name: name, arguments: input.compactJSONString))
            case .toolResult(let toolUseID, let content, let isError):
                flushActiveMessage()
                let output = isError ? "ERROR: \(content)" : content
                items.append(.functionCallOutput(callID: toolUseID, output: output))
            case .passthrough:
                continue
            }
        }
        flushActiveMessage()
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
}

private enum ResponsesMessageContent: Encodable {
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

private struct ResponsesToolNamespace: Encodable {
    var type = "namespace"
    var name = "trainorrest"
    var description = "TrainOrRest coach tools"
    var tools: [ResponsesFunctionTool]

    init(tools: [ClaudeTool]) {
        self.tools = tools.map(ResponsesFunctionTool.init)
    }
}

private struct ResponsesFunctionTool: Encodable {
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

private enum ResponsesToolChoice: Encodable {
    case mode(String)

    init?(from choice: CoachToolCatalog.ToolChoice?) {
        guard let choice else { return nil }
        switch choice {
        case .auto:
            self = .mode("auto")
        case .any:
            self = .mode("required")
        case .tool:
            self = .mode("required")
        @unknown default:
            self = .mode("none")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .mode(let value):
            try container.encode(value)
        }
    }
}

private struct ResponsesStreamTranslator {
    private(set) var completed = false
    private var startedIndices: Set<Int> = []
    private var sawArgumentDelta: Set<Int> = []
    private var sawFunctionCall = false

    mutating func translate(_ message: ResponsesSSEParser.Message) throws -> [AnthropicStreamEvent] {
        guard let payload = try? JSONDecoder().decode(ResponsesStreamPayload.self, from: Data(message.data.utf8)) else {
            throw ClaudeClientError.invalidResponse
        }
        let type = message.event ?? payload.type
        guard let type else { return [] }

        switch type {
        case "response.created":
            return [.messageStart]
        case "response.output_item.added":
            guard let index = payload.outputIndex, let item = payload.item else {
                throw ClaudeClientError.invalidResponse
            }
            switch item.type {
            case "message":
                startedIndices.insert(index)
                return [.contentBlockStart(index: index, kind: .text)]
            case "function_call":
                guard let callID = item.callID, let name = item.name else {
                    throw ClaudeClientError.invalidResponse
                }
                startedIndices.insert(index)
                sawFunctionCall = true
                return [.contentBlockStart(index: index, kind: .toolUse(id: callID, name: name))]
            default:
                return []
            }
        case "response.output_text.delta":
            guard let index = payload.outputIndex else { throw ClaudeClientError.invalidResponse }
            guard startedIndices.contains(index) else { return [] }
            return [.textDelta(index: index, payload.delta ?? "")]
        case "response.function_call_arguments.delta":
            guard let index = payload.outputIndex else { throw ClaudeClientError.invalidResponse }
            guard startedIndices.contains(index) else { return [] }
            sawArgumentDelta.insert(index)
            return [.inputJSONDelta(index: index, payload.delta ?? "")]
        case "response.output_item.done":
            guard let index = payload.outputIndex,
                  let item = payload.item,
                  startedIndices.contains(index) else {
                return []
            }
            startedIndices.remove(index)
            guard item.type == "message" || item.type == "function_call" else { return [] }
            if item.type == "function_call", !sawArgumentDelta.contains(index), let arguments = item.arguments {
                return [
                    .inputJSONDelta(index: index, arguments),
                    .contentBlockStop(index: index)
                ]
            }
            return [.contentBlockStop(index: index)]
        case "response.completed":
            completed = true
            return [
                .messageDelta(stopReason: sawFunctionCall ? "tool_use" : "end_turn"),
                .messageStop
            ]
        case "response.incomplete":
            let reason = payload.response?.incompleteDetails?.reason ?? "unknown"
            throw ClaudeClientError.api("ChatGPT stopped early: \(reason)")
        case "response.failed", "error":
            throw ChatGPTResponsesClient.mapError(
                payload.reportedError,
                status: nil,
                fallback: "ChatGPT stream error."
            )
        default:
            return []
        }
    }
}

private struct ResponsesStreamPayload: Decodable {
    var type: String?
    var outputIndex: Int?
    var delta: String?
    var item: ResponsesOutputItem?
    var response: ResponsesResponse?
    var error: ChatGPTAPIError?
    var code: String?
    var message: String?
    var param: String?

    var reportedError: ChatGPTAPIError? {
        error ?? response?.error ?? {
            guard code != nil || message != nil || param != nil else { return nil }
            return ChatGPTAPIError(code: code, message: message, param: param)
        }()
    }

    enum CodingKeys: String, CodingKey {
        case type, delta, item, response, error, code, message, param
        case outputIndex = "output_index"
    }
}

private struct ResponsesOutputItem: Decodable {
    var type: String
    var callID: String?
    var name: String?
    var arguments: String?

    enum CodingKeys: String, CodingKey {
        case type, name, arguments
        case callID = "call_id"
    }
}

private struct ResponsesResponse: Decodable {
    var error: ChatGPTAPIError?
    var incompleteDetails: ResponsesIncompleteDetails?

    enum CodingKeys: String, CodingKey {
        case error
        case incompleteDetails = "incomplete_details"
    }
}

private struct ResponsesIncompleteDetails: Decodable {
    var reason: String?
}

fileprivate struct ChatGPTAPIError: Decodable {
    var code: String?
    var message: String?
    var param: String?
}

private struct ChatGPTErrorBody: Decodable {
    var error: ChatGPTAPIError?
    var detail: String?
}

private struct ResponsesResponseCollector {
    private enum Block {
        case text(String)
        case tool(id: String, name: String, arguments: String)
    }

    private var activeBlocks: [Int: Block] = [:]
    private var completedBlocks: [Int: ClaudeContentBlock] = [:]
    private var stopReason: String?

    mutating func ingest(_ event: AnthropicStreamEvent) throws {
        switch event {
        case .messageStart:
            activeBlocks.removeAll()
            completedBlocks.removeAll()
            stopReason = nil
        case .contentBlockStart(let index, let kind):
            switch kind {
            case .text:
                activeBlocks[index] = .text("")
            case .toolUse(let id, let name):
                activeBlocks[index] = .tool(id: id, name: name, arguments: "")
            }
        case .textDelta(let index, let delta):
            guard case .text(let text)? = activeBlocks[index] else { return }
            activeBlocks[index] = .text(text + delta)
        case .inputJSONDelta(let index, let delta):
            guard case .tool(let id, let name, let arguments)? = activeBlocks[index] else { return }
            activeBlocks[index] = .tool(id: id, name: name, arguments: arguments + delta)
        case .contentBlockStop(let index):
            guard let block = activeBlocks.removeValue(forKey: index) else { return }
            switch block {
            case .text(let text):
                completedBlocks[index] = .text(text)
            case .tool(let id, let name, let arguments):
                let input = try JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8))
                completedBlocks[index] = .toolUse(id: id, name: name, input: input)
            }
        case .messageDelta(let reason):
            stopReason = reason
        case .messageStop, .passthroughBlock, .ping, .error:
            return
        }
    }

    func response() throws -> ClaudeResponse {
        ClaudeResponse(
            content: completedBlocks.keys.sorted().compactMap { completedBlocks[$0] },
            stopReason: stopReason
        )
    }
}

private extension AnthropicStreamEvent {
    var isResponseContent: Bool {
        switch self {
        case .contentBlockStart, .textDelta, .inputJSONDelta, .contentBlockStop, .passthroughBlock:
            true
        case .messageStart, .messageDelta, .messageStop, .ping, .error:
            false
        }
    }
}

private extension JSONValue {
    var compactJSONString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
