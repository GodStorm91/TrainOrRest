import Foundation
import XCTest
@testable import TrainOrRest

final class GrokClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    override func tearDown() {
        GrokStubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testDeviceAuthorizationRejectsUntrustedVerificationHost() {
        let body = """
        {"device_code":"device","user_code":"ABCD-EFGH","verification_uri":"https://auth.x.ai/activate","verification_uri_complete":"https://evil.example/activate?user_code=ABCD-EFGH","expires_in":600,"interval":5}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try GrokOAuthParsing.deviceAuthorization(from: body, now: now)) { error in
            XCTAssertEqual(error as? GrokOAuthError, .endpointRejected)
        }
    }

    func testTokenParsingUsesRefreshFallbackAndExpirySkew() throws {
        let body = #"{"access_token":"access","expires_in":600}"#.data(using: .utf8)!
        let tokens = try GrokOAuthParsing.tokenSet(from: body, now: now, refreshFallback: "refresh")
        XCTAssertEqual(tokens.accessToken, "access")
        XCTAssertEqual(tokens.refreshToken, "refresh")
        XCTAssertEqual(tokens.expiresAt, now.addingTimeInterval(300))
    }

    func testPollMapsPendingAndDeniedWithoutTreatingThemAsTokens() throws {
        let pending = #"{"error":"authorization_pending"}"#.data(using: .utf8)!
        XCTAssertEqual(try GrokOAuthParsing.poll(status: 400, data: pending, now: now), .pending)
        let denied = #"{"error":"access_denied"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GrokOAuthParsing.poll(status: 400, data: denied, now: now)) { error in
            XCTAssertEqual(error as? GrokOAuthError, .declined)
        }
    }

    func testSignInKeepsPollingAfterTheConnectionDropsWhileTheUserApproves() async throws {
        let attempts = Counter()
        let service = makeOAuthService { request in
            switch attempts.next() {
            case 1: throw URLError(.networkConnectionLost)
            case 2: return (Self.response(for: request, status: 400), Data(#"{"error":"authorization_pending"}"#.utf8))
            default: return (Self.response(for: request, status: 200),
                             Data(#"{"access_token":"grok-access","refresh_token":"grok-refresh","expires_in":3600}"#.utf8))
            }
        }
        let authorization = GrokDeviceAuthorization(
            deviceCode: "device",
            userCode: "CODE",
            verificationURL: URL(string: "https://accounts.x.ai/oauth2/device")!,
            expiresAt: Date().addingTimeInterval(1_800),
            interval: 0.01
        )
        let tokens = try await service.pollUntilComplete(
            authorization,
            tokenEndpoint: URL(string: "https://auth.x.ai/oauth2/token")!
        )
        XCTAssertEqual(tokens.accessToken, "grok-access")
        XCTAssertEqual(attempts.value, 3)
    }

    func testRequestOmitsBillingHeaderAndUsesResponsesToolShape() async throws {
        var captured: URLRequest?
        let client = makeClient { request in
            captured = request
            return (Self.response(for: request, status: 200), Self.textStream())
        }
        var request = Self.request()
        request.tools = [ClaudeTool(name: "plan_edit_draft", description: "Draft a plan edit.", inputSchema: .object(["type": .string("object")]))]
        request.toolChoice = .any

        _ = try await client.send(request, credential: .grok(GrokTokenStub()))

        let sent = try XCTUnwrap(captured)
        XCTAssertEqual(sent.url, GrokAuthConfiguration.responsesURL)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-XAI-Token-Auth"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent.bodyDataForTest)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "grok-4.6")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["tool_choice"] as? String, "required")
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        XCTAssertEqual(tools.first?["name"] as? String, "plan_edit_draft")
        XCTAssertNil(body["max_output_tokens"])
    }

    func testTextAndToolStreamsBecomeCoachContent() async throws {
        let textClient = makeClient { request in
            (Self.response(for: request, status: 200), Self.textStream())
        }
        let text = try await textClient.send(Self.request(), credential: .grok(GrokTokenStub()))
        XCTAssertEqual(text.content, [.text("Steady miles.")])
        XCTAssertEqual(text.stopReason, "end_turn")

        let toolClient = makeClient { request in
            (Self.response(for: request, status: 200), Self.toolStream())
        }
        let tool = try await toolClient.send(Self.request(), credential: .grok(GrokTokenStub()))
        XCTAssertEqual(tool.stopReason, "tool_use")
        guard case .toolUse(let id, let name, let input) = tool.content.first else {
            return XCTFail("Expected a tool call")
        }
        XCTAssertEqual(id, "call_plan")
        XCTAssertEqual(name, "propose_plan_adjustment")
        XCTAssertEqual(input, .object(["changes": .array([.object(["date": .string("2026-07-11"), "action": .string("rest")])])]))
    }

    func testUnauthorizedRefreshesOnceThenFailsClosed() async throws {
        let provider = GrokTokenStub()
        let client = makeClient { request in
            (Self.response(for: request, status: 401), Data("{}".utf8))
        }
        do {
            _ = try await client.send(Self.request(), credential: .grok(provider))
            XCTFail("A repeated 401 must not keep the session")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .api("Your Grok session ended. Sign in again in Settings; your chats are safe."))
        }
        let refreshes = await provider.refreshCount
        XCTAssertEqual(refreshes, 1)
    }

    func testRateLimitStaysRetryableInsteadOfChatGPTPlanCopy() async throws {
        let client = makeClient { request in
            (Self.response(for: request, status: 429), Data(#"{"error":{"message":"slow down"}}"#.utf8))
        }
        do {
            _ = try await client.send(Self.request(), credential: .grok(GrokTokenStub()))
            XCTFail("429 must surface as a retryable limit")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .rateLimited)
        }
    }

    func testRouterSendsGrokThroughItsOwnClient() {
        let grok = MarkerClient(name: "grok")
        let routed = CoachClientRouter.client(
            for: .grok,
            anthropicClient: MarkerClient(name: "anthropic"),
            openAIClient: MarkerClient(name: "openai"),
            chatGPTClient: MarkerClient(name: "chatgpt"),
            grokClient: grok
        )
        XCTAssertTrue(routed as AnyObject === grok)
    }

    func testConnectedGrokStatusUsesGrokCopy() {
        let copy = CoachLanguage.en.settings
        let connected = CoachConnectionStatus(
            selected: .grok,
            chatGPT: .signedOut,
            hasAnthropicKey: false,
            hasOpenAIKey: false,
            grok: .connected(email: "runner@example.com")
        )
        XCTAssertEqual(connected.title(copy), copy.coachConnected)
        XCTAssertEqual(connected.message(copy, model: "grok-4.6"), copy.usingGrok(email: "runner@example.com", model: "grok-4.6"))
        XCTAssertTrue(connected.isConnected)
        XCTAssertFalse(connected.isChatGPTAttention)

        let expired = CoachConnectionStatus(
            selected: .grok,
            chatGPT: .connected(email: "ignored@example.com"),
            hasAnthropicKey: true,
            hasOpenAIKey: true,
            grok: .needsReconnect
        )
        XCTAssertEqual(expired.title(copy), copy.reconnectGrokTitle)
        XCTAssertEqual(expired.action, .reconnect)
        XCTAssertFalse(expired.isConnected)
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> GrokResponsesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GrokStubURLProtocol.self]
        GrokStubURLProtocol.requestHandler = handler
        return GrokResponsesClient(session: URLSession(configuration: configuration))
    }

    private func makeOAuthService(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> GrokOAuthService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GrokStubURLProtocol.self]
        GrokStubURLProtocol.requestHandler = handler
        return GrokOAuthService(session: URLSession(configuration: configuration))
    }

    private static func request() -> ClaudeRequest {
        ClaudeRequest(
            model: "grok-4.6",
            system: "Coach clearly.",
            tools: [],
            messages: [ClaudeMessageParam(role: "user", content: [.text("How should I pace today?")])]
        )
    }

    private static func textStream() -> Data {
        """
        event: response.created
        data: {"type":"response.created","response":{"id":"resp_text"}}

        event: response.output_item.added
        data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","role":"assistant"}}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","output_index":0,"delta":"Steady "}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","output_index":0,"delta":"miles."}

        event: response.output_item.done
        data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","role":"assistant"}}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"resp_text","status":"completed"}}

        """.data(using: .utf8)!
    }

    private static func toolStream() -> Data {
        """
        event: response.created
        data: {"type":"response.created","response":{"id":"resp_tool"}}

        event: response.output_item.added
        data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","call_id":"call_plan","name":"propose_plan_adjustment"}}

        event: response.function_call_arguments.delta
        data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\\"changes\\":["}

        event: response.function_call_arguments.delta
        data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\\"date\\":\\"2026-07-11\\",\\"action\\":\\"rest\\"}"}

        event: response.function_call_arguments.delta
        data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"]}"}

        event: response.output_item.done
        data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","call_id":"call_plan","name":"propose_plan_adjustment","arguments":"{\\"changes\\":[{\\"date\\":\\"2026-07-11\\",\\"action\\":\\"rest\\"}]}"}}

        event: response.completed
        data: {"type":"response.completed","response":{"id":"resp_tool","status":"completed"}}

        """.data(using: .utf8)!
    }

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private actor GrokTokenStub: GrokTokenProviding {
    private(set) var refreshCount = 0

    func accessToken() async throws -> String { "access-token" }

    func refreshAfterUnauthorized() async throws -> String {
        refreshCount += 1
        return "refreshed-token"
    }
}

private final class MarkerClient: ClaudeServicing {
    let name: String
    init(name: String) { self.name = name }
    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        ClaudeResponse(content: [], stopReason: name)
    }
}

private final class GrokStubURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
