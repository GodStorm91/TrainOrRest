import Foundation
import XCTest
@testable import TrainOrRest

final class ChatGPTResponsesClientTests: XCTestCase {
    override func tearDown() {
        ResponsesStubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRequestUsesSIWCRequiredFieldsOnly() async throws {
        var capturedBody: [String: Any] = [:]
        let client = makeClient { request in
            let data = try XCTUnwrap(request.bodyDataForTest)
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (Self.response(for: request, status: 200), try self.fixtureData(named: "text", extension: "sse"))
        }

        _ = try await client.send(Self.request(), credential: .chatGPT(ResponsesTokenProvider()))

        let keys = Set(capturedBody.keys)
        XCTAssertTrue(Set(["model", "instructions", "input", "store", "stream"]).isSubset(of: keys))
        XCTAssertFalse(keys.contains("max_output_tokens"))
        XCTAssertFalse(keys.contains("temperature"))
        XCTAssertFalse(keys.contains("metadata"))
        XCTAssertFalse(keys.contains("previous_response_id"))
        XCTAssertFalse(keys.contains("user"))
        XCTAssertFalse(keys.contains("truncation"))
        XCTAssertFalse(keys.contains("prompt"))
        XCTAssertFalse(keys.contains("background"))
        XCTAssertFalse(keys.contains("conversation"))
        XCTAssertFalse(keys.contains("max_tool_calls"))
        XCTAssertFalse(keys.contains("top_p"))
        XCTAssertFalse(keys.contains("safety_identifier"))
        XCTAssertFalse(keys.contains("prompt_cache_retention"))
        XCTAssertEqual(capturedBody["store"] as? Bool, false)
        XCTAssertEqual(capturedBody["stream"] as? Bool, true)
        XCTAssertEqual(capturedBody["instructions"] as? String, "Coach clearly.")
    }

    func testToolChoicesUseNamespacesAndRequiredFallback() async throws {
        let first = Self.tool(name: "first")
        let second = Self.tool(name: "second")

        let autoBody = try await sendAndCaptureBody(tools: [first, second], choice: .auto)
        XCTAssertEqual(autoBody["tool_choice"] as? String, "auto")
        XCTAssertEqual(Self.namespaceToolNames(in: autoBody), ["first", "second"])

        let anyBody = try await sendAndCaptureBody(tools: [first, second], choice: .any)
        XCTAssertEqual(anyBody["tool_choice"] as? String, "required")
        XCTAssertEqual(Self.namespaceToolNames(in: anyBody), ["first", "second"])

        let forcedBody = try await sendAndCaptureBody(tools: [first, second], choice: .tool(name: "second"))
        XCTAssertEqual(forcedBody["tool_choice"] as? String, "required")
        XCTAssertEqual(Self.namespaceToolNames(in: forcedBody), ["second"])
    }

    func testImagesAndToolTurnsPreserveDataAndCallIDs() async throws {
        var capturedBody: [String: Any] = [:]
        let client = makeClient { request in
            let data = try XCTUnwrap(request.bodyDataForTest)
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (Self.response(for: request, status: 200), Self.completedStream())
        }
        let request = ClaudeRequest(
            model: "gpt-5.5",
            system: "Coach clearly.",
            tools: [],
            messages: [
                ClaudeMessageParam(role: "user", content: [
                    .text("Review this."),
                    .image(mediaType: "image/jpeg", data: "aGVsbG8=")
                ]),
                ClaudeMessageParam(role: "assistant", content: [
                    .toolUse(id: "call_plan", name: "make_plan", input: .object(["day": .string("Tuesday")]))
                ]),
                ClaudeMessageParam(role: "user", content: [
                    .toolResult(toolUseID: "call_plan", content: "unavailable", isError: true)
                ])
            ]
        )

        _ = try await client.send(request, credential: .chatGPT(ResponsesTokenProvider()))

        let input = try XCTUnwrap(capturedBody["input"] as? [[String: Any]])
        let userContent = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(userContent[1]["type"] as? String, "input_image")
        XCTAssertEqual(userContent[1]["image_url"] as? String, "data:image/jpeg;base64,aGVsbG8=")
        XCTAssertEqual(input[1]["type"] as? String, "function_call")
        XCTAssertEqual(input[1]["call_id"] as? String, "call_plan")
        XCTAssertEqual(input[2]["type"] as? String, "function_call_output")
        XCTAssertEqual(input[2]["call_id"] as? String, "call_plan")
        XCTAssertEqual(input[2]["output"] as? String, "ERROR: unavailable")
    }

    func testTextStreamAccumulatesResponsesText() async throws {
        let client = makeClient { request in
            (Self.response(for: request, status: 200), try self.fixtureData(named: "text", extension: "sse"))
        }

        let response = try await client.send(Self.request(), credential: .chatGPT(ResponsesTokenProvider()))

        XCTAssertEqual(response.content, [.text("Steady miles.")])
        XCTAssertEqual(response.stopReason, "end_turn")
    }

    func testToolCallStreamDecodesFullArgumentsAndToolStopReason() async throws {
        let client = makeClient { request in
            (Self.response(for: request, status: 200), try self.fixtureData(named: "tool-call", extension: "sse"))
        }

        let response = try await client.send(Self.request(), credential: .chatGPT(ResponsesTokenProvider()))

        XCTAssertEqual(
            response.content,
            [
                .toolUse(
                    id: "call_plan",
                    name: "propose_plan_adjustment",
                    input: .object([
                        "changes": .array([
                            .object(["date": .string("2026-07-11"), "action": .string("rest")])
                        ])
                    ])
                )
            ]
        )
        XCTAssertEqual(response.stopReason, "tool_use")
    }

    func testMissingCompletedEventFailsAsConnectionLost() async throws {
        var requestCount = 0
        let client = makeClient { request in
            requestCount += 1
            return (Self.response(for: request, status: 200), try self.fixtureData(named: "missing-completed", extension: "sse"))
        }

        do {
            _ = try await client.send(Self.request(), credential: .chatGPT(ResponsesTokenProvider()))
            XCTFail("A partial Responses stream must not succeed")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .connectionLost)
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testUsageLimitStreamFailureRecordsPlanError() async throws {
        let provider = ResponsesTokenProvider()
        let client = makeClient { request in
            (Self.response(for: request, status: 200), try self.fixtureData(named: "usage-limit", extension: "sse"))
        }

        do {
            _ = try await client.send(Self.request(), credential: .chatGPT(provider))
            XCTFail("Usage-limit stream failures must not succeed")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .planUsageLimit)
        }
        let recordedErrors = await provider.recordedErrors()
        XCTAssertEqual(recordedErrors, [.planUsageLimit])
    }

    func testUnauthorizedRequestRefreshesOnceThenRetries() async throws {
        let provider = ResponsesTokenProvider(accessToken: "stale", refreshedToken: "fresh")
        var authorizations: [String] = []
        let client = makeClient { request in
            authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            if authorizations.count == 1 {
                return (Self.response(for: request, status: 401), Data())
            }
            return (Self.response(for: request, status: 200), try self.fixtureData(named: "text", extension: "sse"))
        }

        _ = try await client.send(Self.request(), credential: .chatGPT(provider))

        XCTAssertEqual(authorizations, ["Bearer stale", "Bearer fresh"])
        let refreshCount = await provider.refreshCount()
        XCTAssertEqual(refreshCount, 1)
    }

    func testSecondUnauthorizedRequestNeedsReconnect() async throws {
        let provider = ResponsesTokenProvider()
        var requestCount = 0
        let client = makeClient { request in
            requestCount += 1
            return (Self.response(for: request, status: 401), Data())
        }

        do {
            _ = try await client.send(Self.request(), credential: .chatGPT(provider))
            XCTFail("A second unauthorized Responses request must reconnect")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .needsReconnect)
        }
        XCTAssertEqual(requestCount, 2)
        let refreshCount = await provider.refreshCount()
        let recordedErrors = await provider.recordedErrors()
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(recordedErrors, [.needsReconnect])
    }

    func testDetailErrorBodyIsReported() async throws {
        let client = makeClient { request in
            (
                Self.response(for: request, status: 403),
                #"{"detail":"serving region is unavailable"}"#.data(using: .utf8)!
            )
        }

        do {
            _ = try await client.send(Self.request(), credential: .chatGPT(ResponsesTokenProvider()))
            XCTFail("Direct admission errors must not succeed")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .api("serving region is unavailable"))
        }
    }

    func testNonChatGPTCredentialNeedsReconnect() async throws {
        let client = ChatGPTResponsesClient()

        do {
            _ = try await client.send(Self.request(), credential: .apiKey("not-a-chatgpt-token"))
            XCTFail("The Responses client only accepts ChatGPT credentials")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .needsReconnect)
        }
    }

    private func sendAndCaptureBody(
        tools: [ClaudeTool],
        choice: CoachToolCatalog.ToolChoice
    ) async throws -> [String: Any] {
        var capturedBody: [String: Any] = [:]
        let client = makeClient { request in
            let data = try XCTUnwrap(request.bodyDataForTest)
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (Self.response(for: request, status: 200), Self.completedStream())
        }
        var request = Self.request()
        request.tools = tools
        request.toolChoice = choice
        _ = try await client.send(request, credential: .chatGPT(ResponsesTokenProvider()))
        return capturedBody
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> ChatGPTResponsesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResponsesStubURLProtocol.self]
        ResponsesStubURLProtocol.requestHandler = handler
        return ChatGPTResponsesClient(session: URLSession(configuration: configuration))
    }

    private func fixtureData(named name: String, extension fileExtension: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures/Responses")
                ?? bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Responses")
                ?? bundle.url(forResource: name, withExtension: fileExtension)
        )
        return try Data(contentsOf: url)
    }

    private static func request() -> ClaudeRequest {
        ClaudeRequest(
            model: "gpt-5.5",
            system: "Coach clearly.",
            tools: [],
            messages: [ClaudeMessageParam(role: "user", content: [.text("How should I pace today?")])]
        )
    }

    private static func tool(name: String) -> ClaudeTool {
        ClaudeTool(
            name: name,
            description: "\(name) description",
            inputSchema: .object(["type": .string("object")])
        )
    }

    private static func namespaceToolNames(in body: [String: Any]) -> [String] {
        let namespaces = body["tools"] as? [[String: Any]]
        let tools = namespaces?.first?["tools"] as? [[String: Any]]
        return tools?.compactMap { $0["name"] as? String } ?? []
    }

    private static func completedStream() -> Data {
        """
        event: response.created
        data: {"type":"response.created","response":{"id":"resp_done"}}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"resp_done","status":"completed"}}
        """.data(using: .utf8)!
    }

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

private actor ResponsesTokenProvider: ChatGPTTokenProviding {
    private let currentAccessToken: String
    private let replacementAccessToken: String
    private var refreshes = 0
    private var errors: [ClaudeClientError] = []

    init(accessToken: String = "token", refreshedToken: String = "refreshed-token") {
        currentAccessToken = accessToken
        replacementAccessToken = refreshedToken
    }

    func accessToken() async throws -> String {
        currentAccessToken
    }

    func refreshAfterUnauthorized() async throws -> String {
        refreshes += 1
        return replacementAccessToken
    }

    func recordPlanError(_ error: ClaudeClientError) async {
        errors.append(error)
    }

    func refreshCount() -> Int {
        refreshes
    }

    func recordedErrors() -> [ClaudeClientError] {
        errors
    }
}

private final class ResponsesStubURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: ClaudeClientError.invalidResponse)
            return
        }
        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
