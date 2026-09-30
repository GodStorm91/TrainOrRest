import AuthenticationServices
import Foundation
import XCTest
@testable import TrainOrRest

final class ChatGPTTokenStoreTests: XCTestCase {
    override func tearDown() {
        ChatGPTStubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testConcurrentExpiredTokenRefreshesOnceAndPersistsRotationBeforeReturning() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let keychain = InMemoryChatGPTKeychain(record: credential(expiresAt: now.addingTimeInterval(-1)))
        let requestCount = LockedInt()
        let session = stubbedSession { request in
            XCTAssertEqual(request.url, ChatGPTAuthConfiguration.tokenEndpoint)
            requestCount.increment()
            return Self.response(
                status: 200,
                body: Self.tokenBody(access: "rotated-access", refresh: "rotated-refresh", expiresIn: 3_600)
            )
        }
        let store = ChatGPTTokenStore(keychain: keychain, session: session, now: { now }, oauthService: NoopOAuthService(), idTokenValidator: NoopIDTokenValidator())

        let tokens = try await withThrowingTaskGroup(of: String.self, returning: [String].self) { group in
            for _ in 0..<10 {
                group.addTask { try await store.accessToken() }
            }
            var tokens = [String]()
            for try await token in group { tokens.append(token) }
            return tokens
        }

        XCTAssertEqual(tokens, Array(repeating: "rotated-access", count: 10))
        XCTAssertEqual(requestCount.value, 1)
        XCTAssertEqual(keychain.record()?.refreshToken, "rotated-refresh")
    }

    func testRefreshTokenReusedRequiresReconnectAndKeepsClientID() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let keychain = InMemoryChatGPTKeychain(record: credential(expiresAt: now.addingTimeInterval(-1)))
        let session = stubbedSession { _ in
            Self.response(status: 400, body: #"{"error":{"code":"refresh_token_reused"}}"#.data(using: .utf8)!)
        }
        let store = ChatGPTTokenStore(keychain: keychain, session: session, now: { now }, oauthService: NoopOAuthService(), idTokenValidator: NoopIDTokenValidator())

        do {
            _ = try await store.accessToken()
            XCTFail("Expected a terminal refresh error")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .needsReconnect)
        }

        XCTAssertEqual(store.state, .needsReconnect)
        XCTAssertEqual(keychain.record()?.clientID, "oaiapp_test")
        XCTAssertEqual(keychain.record()?.refreshToken, "")
    }

    func testNetworkErrorKeepsCredentials() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = credential(expiresAt: now.addingTimeInterval(-1))
        let keychain = InMemoryChatGPTKeychain(record: initial)
        let session = stubbedSession { _ in throw URLError(.notConnectedToInternet) }
        let store = ChatGPTTokenStore(keychain: keychain, session: session, now: { now }, oauthService: NoopOAuthService(), idTokenValidator: NoopIDTokenValidator())

        do {
            _ = try await store.accessToken()
            XCTFail("Expected offline error")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .offline)
        }

        XCTAssertEqual(keychain.record(), initial)
        XCTAssertEqual(store.state, .connected(email: "runner@example.com"))
    }

    func testEarliestRefreshAtDefersRefreshWhileTokenIsUnexpired() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let keychain = InMemoryChatGPTKeychain(record: credential(
            expiresAt: now.addingTimeInterval(60),
            earliestRefreshAt: now.addingTimeInterval(3_600)
        ))
        let requestCount = LockedInt()
        let session = stubbedSession { _ in
            requestCount.increment()
            return Self.response(status: 500, body: Data())
        }
        let store = ChatGPTTokenStore(keychain: keychain, session: session, now: { now }, oauthService: NoopOAuthService(), idTokenValidator: NoopIDTokenValidator())

        let token = try await store.accessToken()
        XCTAssertEqual(token, "access-token")
        XCTAssertEqual(requestCount.value, 0)
    }

    func testSignOutRevokesThenClearsTokensAndKeepsClientID() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let keychain = InMemoryChatGPTKeychain(record: credential(expiresAt: now.addingTimeInterval(3_600)))
        let didRevoke = LockedBool()
        let session = stubbedSession { request in
            XCTAssertEqual(request.url, ChatGPTAuthConfiguration.revocationEndpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            let body = String(data: request.bodyDataForTest ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("refresh_token"))
            XCTAssertTrue(body.contains("client_id=oaiapp_test"))
            didRevoke.set(true)
            return Self.response(status: 200, body: Data())
        }
        let store = ChatGPTTokenStore(keychain: keychain, session: session, now: { now }, oauthService: NoopOAuthService(), idTokenValidator: NoopIDTokenValidator())

        let revoked = await store.signOut()
        XCTAssertTrue(revoked)
        XCTAssertTrue(didRevoke.value)
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(keychain.record()?.clientID, "oaiapp_test")
        XCTAssertEqual(keychain.record()?.idToken, "")
        XCTAssertEqual(keychain.record()?.accessToken, "")
        XCTAssertEqual(keychain.record()?.refreshToken, "")
    }

    private func credential(expiresAt: Date, earliestRefreshAt: Date? = nil) -> ChatGPTCredentialRecord {
        ChatGPTCredentialRecord(
            issuer: ChatGPTAuthConfiguration.issuer,
            subject: "subject-1",
            email: "runner@example.com",
            clientID: "oaiapp_test",
            idToken: "id-token",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: expiresAt,
            earliestRefreshAt: earliestRefreshAt,
            scopes: [ChatGPTAuthConfiguration.planScope, "openid"]
        )
    }

    private func stubbedSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        ChatGPTStubURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatGPTStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(status: Int, body: Data) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: ChatGPTAuthConfiguration.tokenEndpoint,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, body)
    }

    private static func tokenBody(access: String, refresh: String, expiresIn: Int) -> Data {
        #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","id_token":"new-id-token","expires_in":\#(expiresIn),"scope":"openid chatgpt.tokens.use.direct"}"#
            .data(using: .utf8)!
    }
}

private final class InMemoryChatGPTKeychain: ChatGPTKeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    init(record: ChatGPTCredentialRecord? = nil) {
        if let record,
           let data = try? JSONEncoder().encode(record),
           let value = String(data: data, encoding: .utf8) {
            values[KeychainStore.chatGPTCredentialAccount] = value
        }
    }

    func load(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func save(_ value: String, account: String) throws {
        lock.lock()
        values[account] = value
        lock.unlock()
    }

    func delete(account: String) throws {
        lock.lock()
        values.removeValue(forKey: account)
        lock.unlock()
    }

    func record() -> ChatGPTCredentialRecord? {
        guard let value = try? load(account: KeychainStore.chatGPTCredentialAccount),
              let data = value.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ChatGPTCredentialRecord.self, from: data)
    }
}

private final class NoopOAuthService: ChatGPTOAuthServicing, @unchecked Sendable {
    func authorize(
        presentationAnchor: ASPresentationAnchor,
        hostID: String,
        existingRegistration: ChatGPTExistingRegistration?,
        requestConsent: Bool
    ) async throws -> ChatGPTAuthorizationResult {
        throw ChatGPTOAuthError.cancelled
    }
}

private final class NoopIDTokenValidator: ChatGPTIDTokenValidating, @unchecked Sendable {
    func validate(
        idToken: String,
        clientID: String,
        nonce: String,
        expectedSubject: String?
    ) async throws -> ChatGPTIDTokenClaims {
        throw IDTokenValidationError.malformedToken
    }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Bool) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

private final class ChatGPTStubURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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
