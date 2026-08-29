import Foundation
import XCTest
@testable import TrainOrRest

final class OpenAIClientTests: XCTestCase {
    override func tearDown() {
        OpenAIStubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testGPT5RequestsUseMinimalReasoningToLeaveAnswerBudget() async throws {
        var capturedBody: [String: Any] = [:]
        let client = makeClient { request in
            let body = try XCTUnwrap(request.bodyDataForTest)
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Self.textResponse("OK"))
        }

        _ = try await client.send(Self.request(model: "gpt-5-nano"), apiKey: "test-key")

        XCTAssertEqual(capturedBody["model"] as? String, "gpt-5-nano")
        XCTAssertEqual(capturedBody["reasoning_effort"] as? String, "minimal")
        XCTAssertEqual(capturedBody["max_completion_tokens"] as? Int, CoachChatConfig.maxOutputTokens)
    }

    func testNonGPT5RequestsDoNotSendReasoningEffort() async throws {
        var capturedBody: [String: Any] = [:]
        let client = makeClient { request in
            let body = try XCTUnwrap(request.bodyDataForTest)
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Self.textResponse("OK"))
        }

        _ = try await client.send(Self.request(model: "gpt-4o-mini"), apiKey: "test-key")

        XCTAssertNil(capturedBody["reasoning_effort"])
    }

    func testNamedToolChoiceEncodesAsFunctionChoice() async throws {
        var capturedBody: [String: Any] = [:]
        let client = makeClient { request in
            let body = try XCTUnwrap(request.bodyDataForTest)
            capturedBody = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Self.textResponse("OK"))
        }

        var request = Self.request(model: "gpt-5-nano")
        request.tools = [CoachToolCatalog.coachResponse]
        request.toolChoice = .tool(name: CoachToolCatalog.coachResponseName)
        _ = try await client.send(request, apiKey: "test-key")

        let toolChoice = try XCTUnwrap(capturedBody["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "function")
        let function = try XCTUnwrap(toolChoice["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, CoachToolCatalog.coachResponseName)
    }

    func testEmptyChoicesThrowsInvalidResponseInsteadOfFallbackText() async throws {
        let client = makeClient { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, #"{"choices":[]}"#.data(using: .utf8)!)
        }

        do {
            _ = try await client.send(Self.request(model: "gpt-5-nano"), apiKey: "test-key")
            XCTFail("Empty OpenAI choices must not become a fake assistant response")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testEmptyMessageThrowsInvalidResponseInsteadOfFallbackText() async throws {
        let client = makeClient { request in
            let data = #"{"choices":[{"message":{"content":"   "},"finish_reason":"stop"}]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        do {
            _ = try await client.send(Self.request(model: "gpt-5-nano"), apiKey: "test-key")
            XCTFail("Empty OpenAI content must not become a fake assistant response")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> OpenAIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIStubURLProtocol.self]
        OpenAIStubURLProtocol.requestHandler = handler
        return OpenAIClient(session: URLSession(configuration: configuration))
    }

    private static func request(model: String) -> ClaudeRequest {
        ClaudeRequest(
            model: model,
            system: "Reply briefly.",
            tools: [],
            messages: [ClaudeMessageParam(role: "user", content: [.text("Say OK")])]
        )
    }

    private static func textResponse(_ text: String) -> Data {
        #"{"choices":[{"message":{"content":"\#(text)"},"finish_reason":"stop"}]}"#.data(using: .utf8)!
    }
}

private extension URLRequest {
    var bodyDataForTest: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class OpenAIStubURLProtocol: URLProtocol {
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
