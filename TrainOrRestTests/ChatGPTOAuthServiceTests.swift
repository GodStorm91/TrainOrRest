import Foundation
import XCTest
@testable import TrainOrRest

final class ChatGPTOAuthServiceTests: XCTestCase {
    func testStateMismatchIsRejected() {
        let attempt = newRegistrationAttempt(state: "expected-state")
        let callback = callbackURL(query: ["code": "code", "client_id": "oaiapp_issued", "state": "other-state"])

        XCTAssertThrowsError(try ChatGPTOAuthService.validateCallback(callback, attempt: attempt)) { error in
            XCTAssertEqual(error as? ChatGPTOAuthError, .stateMismatch)
        }
    }

    func testAccessDeniedIsRejectedBeforeCodeExchange() {
        let attempt = newRegistrationAttempt()
        let callback = callbackURL(query: ["error": "access_denied", "state": attempt.state])

        XCTAssertThrowsError(try ChatGPTOAuthService.validateCallback(callback, attempt: attempt)) { error in
            XCTAssertEqual(error as? ChatGPTOAuthError, .declined)
        }
    }

    func testNewRegistrationRequiresIssuedClientID() {
        let attempt = newRegistrationAttempt()
        let callback = callbackURL(query: ["code": "code", "state": attempt.state])

        XCTAssertThrowsError(try ChatGPTOAuthService.validateCallback(callback, attempt: attempt)) { error in
            XCTAssertEqual(error as? ChatGPTOAuthError, .incompleteRegistration)
        }
    }

    func testReauthorizationURLUsesIdentityHintsWithoutAgentName() throws {
        let attempt = ChatGPTOAuthService.makeAuthorizationAttempt(
            hostID: "urn:uuid:host",
            existingRegistration: ChatGPTExistingRegistration(
                clientID: "oaiapp_saved",
                idTokenHint: "retained-id-token",
                loginHint: "runner@example.com"
            ),
            requestConsent: false,
            redirectURI: ChatGPTAuthConfiguration.callbackURL(port: 1234),
            state: "state",
            nonce: "nonce",
            codeVerifier: "verifier"
        )

        let items = try queryItems(for: ChatGPTOAuthService.authorizationURL(for: attempt))
        XCTAssertEqual(items["client_id"], "oaiapp_saved")
        XCTAssertEqual(items["id_token_hint"], "retained-id-token")
        XCTAssertEqual(items["login_hint"], "runner@example.com")
        XCTAssertNil(items["agent_name_hint"])
    }

    func testNewRegistrationURLUsesDynamicClientAndAgentName() throws {
        let attempt = newRegistrationAttempt()

        let items = try queryItems(for: ChatGPTOAuthService.authorizationURL(for: attempt))
        XCTAssertEqual(items["client_id"], ChatGPTAuthConfiguration.registrationClientID)
        XCTAssertEqual(items["agent_name_hint"], ChatGPTAuthConfiguration.agentName)
    }

    func testPKCEChallengeMatchesRFC7636AppendixB() {
        XCTAssertEqual(
            ChatGPTOAuthService.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testCallbackRequestLineParserAcceptsConfiguredPathAndRejectsOtherPaths() {
        let request = Data("GET /auth/callback?code=abc&state=state HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        let callback = LoopbackCallbackListener.callbackURL(fromRequestHeaders: request, port: 4567)
        XCTAssertEqual(callback?.absoluteString, "http://127.0.0.1:4567/auth/callback?code=abc&state=state")

        let favicon = Data("GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        XCTAssertNil(LoopbackCallbackListener.callbackURL(fromRequestHeaders: favicon, port: 4567))
    }

    private func newRegistrationAttempt(state: String = "state") -> ChatGPTAuthorizationAttempt {
        ChatGPTOAuthService.makeAuthorizationAttempt(
            hostID: "urn:uuid:host",
            existingRegistration: nil,
            requestConsent: false,
            redirectURI: ChatGPTAuthConfiguration.callbackURL(port: 1234),
            state: state,
            nonce: "nonce",
            codeVerifier: "verifier"
        )
    }

    private func callbackURL(query: [String: String]) -> URL {
        var components = URLComponents(url: ChatGPTAuthConfiguration.callbackURL(port: 1234), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private func queryItems(for url: URL) throws -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            throw ChatGPTOAuthError.invalidCallback
        }
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
