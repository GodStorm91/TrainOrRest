import Foundation
import XCTest
@testable import TrainOrRest

final class ChatGPTModelCatalogTests: XCTestCase {
    override func tearDown() {
        ModelCatalogStubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testModelsKeepListedEntriesInServerOrder() async throws {
        let catalog = makeCatalog(data: try fixtureData(named: "models"))

        let models = try await catalog.models(tokenProvider: ModelCatalogTokenProvider())

        XCTAssertEqual(
            models,
            [
                ChatGPTModel(id: "gpt-5-mini", displayName: "GPT-5 Mini"),
                ChatGPTModel(id: "gpt-5.4", displayName: "GPT-5.4"),
                ChatGPTModel(id: "gpt-5.5", displayName: "GPT-5.5")
            ]
        )
    }

    func testDefaultModelUsesPreferredOrderBeforeServerOrder() {
        XCTAssertEqual(
            ChatGPTModelCatalog.defaultModel(from: [
                ChatGPTModel(id: "gpt-5-mini", displayName: "Mini"),
                ChatGPTModel(id: "gpt-5.4", displayName: "GPT-5.4"),
                ChatGPTModel(id: "gpt-5.5", displayName: "GPT-5.5")
            ]),
            "gpt-5.5"
        )
        XCTAssertEqual(
            ChatGPTModelCatalog.defaultModel(from: [
                ChatGPTModel(id: "account-model", displayName: "Account model")
            ]),
            "account-model"
        )
    }

    func testResolveSelectedModelKeepsListedSelectionAndReplacesDelistedOrEmptyValues() async throws {
        let suiteName = "ChatGPTModelCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let catalog = makeCatalog(data: try fixtureData(named: "models"), defaults: defaults)
        let provider = ModelCatalogTokenProvider()
        let storageKey = CoachConnection.chatGPT.modelStorageKey

        defaults.set("gpt-5.4", forKey: storageKey)
        let listedSelection = try await catalog.resolveSelectedModel(tokenProvider: provider)
        XCTAssertEqual(listedSelection, "gpt-5.4")

        defaults.set("delisted-model", forKey: storageKey)
        let replacementSelection = try await catalog.resolveSelectedModel(tokenProvider: provider)
        XCTAssertEqual(replacementSelection, "gpt-5.5")
        XCTAssertEqual(defaults.string(forKey: storageKey), "gpt-5.5")

        defaults.set("", forKey: storageKey)
        let emptySelection = try await catalog.resolveSelectedModel(tokenProvider: provider)
        XCTAssertEqual(emptySelection, "gpt-5.5")
        XCTAssertEqual(defaults.string(forKey: storageKey), "gpt-5.5")
    }

    private func makeCatalog(data: Data, defaults: UserDefaults = .standard) -> ChatGPTModelCatalog {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogStubURLProtocol.self]
        ModelCatalogStubURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }
        return ChatGPTModelCatalog(session: URLSession(configuration: configuration), defaults: defaults)
    }

    private func fixtureData(named name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Responses")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Responses")
                ?? bundle.url(forResource: name, withExtension: "json")
        )
        return try Data(contentsOf: url)
    }
}

private actor ModelCatalogTokenProvider: ChatGPTTokenProviding {
    func accessToken() async throws -> String { "token" }

    func refreshAfterUnauthorized() async throws -> String { "refreshed-token" }

    func recordPlanError(_ error: ClaudeClientError) async {}
}

private final class ModelCatalogStubURLProtocol: URLProtocol {
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
