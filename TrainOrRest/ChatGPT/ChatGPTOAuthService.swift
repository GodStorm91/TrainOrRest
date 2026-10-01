import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum ChatGPTOAuthError: Error, Equatable, LocalizedError {
    case cancelled
    case declined
    case stateMismatch
    case invalidCallback
    case incompleteRegistration
    case unexpectedClientID
    case invalidGrant(clientID: String)
    case exchangeFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: "ChatGPT sign-in was cancelled."
        case .declined: "ChatGPT plan usage was not enabled."
        case .stateMismatch, .invalidCallback, .incompleteRegistration, .unexpectedClientID, .exchangeFailed:
            "ChatGPT sign-in could not be completed."
        case .invalidGrant:
            "ChatGPT sign-in expired. Please try again."
        }
    }
}

struct ChatGPTExistingRegistration: Sendable, Equatable {
    let clientID: String
    let idTokenHint: String?
    let loginHint: String?

    init(clientID: String, idTokenHint: String?, loginHint: String?) {
        self.clientID = clientID
        self.idTokenHint = idTokenHint
        self.loginHint = loginHint
    }
}

struct ChatGPTAuthorizationAttempt: Sendable, Equatable {
    let clientID: String
    let isNewRegistration: Bool
    let redirectURI: URL
    let state: String
    let nonce: String
    let codeVerifier: String
    let hostID: String
    let requestConsent: Bool
    let idTokenHint: String?
    let loginHint: String?
}

struct ChatGPTTokenResponse: Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let expiresIn: TimeInterval
    let scope: String?
    let earliestRefreshAt: Date?

    var scopes: Set<String> {
        Set((scope ?? "").split(separator: " ").map(String.init))
    }
}

struct ChatGPTAuthorizationResult: Sendable {
    let clientID: String
    let nonce: String
    let tokenResponse: ChatGPTTokenResponse
}

protocol ChatGPTOAuthServicing: Sendable {
    func authorize(
        presentationAnchor: ASPresentationAnchor,
        hostID: String,
        existingRegistration: ChatGPTExistingRegistration?,
        requestConsent: Bool
    ) async throws -> ChatGPTAuthorizationResult
}

final class ChatGPTOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding, ChatGPTOAuthServicing, @unchecked Sendable {
    private enum AuthorizationEvent: Sendable {
        case callback(URL)
        case browserCompleted(URL)
    }
    private let session: URLSession
    private let listenerFactory: @Sendable () -> LoopbackCallbackListener

    private let authenticationLock = NSLock()
    private var authenticationSession: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?

    nonisolated init(
        session: URLSession = .shared,
        listenerFactory: @escaping @Sendable () -> LoopbackCallbackListener = { LoopbackCallbackListener() }
    ) {
        self.session = session
        self.listenerFactory = listenerFactory
    }

    func authorize(
        presentationAnchor: ASPresentationAnchor,
        hostID: String,
        existingRegistration: ChatGPTExistingRegistration?,
        requestConsent: Bool
    ) async throws -> ChatGPTAuthorizationResult {
        let listener = listenerFactory()
        let port = try await listener.start()
        defer { listener.cancel() }

        let attempt = Self.makeAuthorizationAttempt(
            hostID: hostID,
            existingRegistration: existingRegistration,
            requestConsent: requestConsent,
            redirectURI: ChatGPTAuthConfiguration.callbackURL(port: port)
        )
        let authorizationURL = try Self.authorizationURL(for: attempt)
        let callbackURL = try await waitForCallbackAndBrowserCompletion(
            listener: listener,
            authorizationURL: authorizationURL,
            presentationAnchor: presentationAnchor
        )
        let callback = try Self.validateCallback(callbackURL, attempt: attempt)

        do {
            let tokenResponse = try await exchangeCode(callback.code, clientID: callback.clientID, attempt: attempt)
            return ChatGPTAuthorizationResult(clientID: callback.clientID, nonce: attempt.nonce, tokenResponse: tokenResponse)
        } catch let error as ChatGPTOAuthError {
            throw error
        } catch {
            throw ChatGPTOAuthError.exchangeFailed
        }
    }

    nonisolated static func makeAuthorizationAttempt(
        hostID: String,
        existingRegistration: ChatGPTExistingRegistration?,
        requestConsent: Bool,
        redirectURI: URL,
        state: String = randomURLSafeString(byteCount: 32),
        nonce: String = randomURLSafeString(byteCount: 32),
        codeVerifier: String = randomURLSafeString(byteCount: 32)
    ) -> ChatGPTAuthorizationAttempt {
        ChatGPTAuthorizationAttempt(
            clientID: existingRegistration?.clientID ?? ChatGPTAuthConfiguration.registrationClientID,
            isNewRegistration: existingRegistration == nil,
            redirectURI: redirectURI,
            state: state,
            nonce: nonce,
            codeVerifier: codeVerifier,
            hostID: hostID,
            requestConsent: requestConsent,
            idTokenHint: existingRegistration?.idTokenHint,
            loginHint: existingRegistration?.loginHint
        )
    }

    nonisolated static func authorizationURL(for attempt: ChatGPTAuthorizationAttempt) throws -> URL {
        var components = URLComponents(url: ChatGPTAuthConfiguration.authorizationEndpoint, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "client_id", value: attempt.clientID),
            URLQueryItem(name: "redirect_uri", value: attempt.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: ChatGPTAuthConfiguration.scope),
            URLQueryItem(name: "resource", value: ChatGPTAuthConfiguration.resource),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "nonce", value: attempt.nonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge(for: attempt.codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "ext_agent_host_id", value: attempt.hostID)
        ]

        if attempt.isNewRegistration {
            queryItems.append(URLQueryItem(name: "agent_name_hint", value: ChatGPTAuthConfiguration.agentName))
        } else {
            if let idTokenHint = attempt.idTokenHint, !idTokenHint.isEmpty {
                queryItems.append(URLQueryItem(name: "id_token_hint", value: idTokenHint))
            }
            if let loginHint = attempt.loginHint, !loginHint.isEmpty {
                queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
            }
        }
        if attempt.requestConsent {
            queryItems.append(URLQueryItem(name: "prompt", value: "consent"))
        }

        components?.queryItems = queryItems
        guard let url = components?.url else { throw ChatGPTOAuthError.invalidCallback }
        return url
    }

    nonisolated static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    nonisolated static func validateCallback(
        _ callbackURL: URL,
        attempt: ChatGPTAuthorizationAttempt
    ) throws -> (code: String, clientID: String) {
        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in queryItems.first(where: { $0.name == name })?.value }

        guard value("state") == attempt.state else { throw ChatGPTOAuthError.stateMismatch }
        if value("error") == "access_denied" { throw ChatGPTOAuthError.declined }
        if value("error") != nil { throw ChatGPTOAuthError.invalidCallback }

        guard let code = value("code"), !code.isEmpty else { throw ChatGPTOAuthError.invalidCallback }
        let returnedClientID = value("client_id")?.trimmingCharacters(in: .whitespacesAndNewlines)

        if attempt.isNewRegistration {
            guard let clientID = returnedClientID,
                  !clientID.isEmpty,
                  clientID != ChatGPTAuthConfiguration.registrationClientID else {
                throw ChatGPTOAuthError.incompleteRegistration
            }
            return (code, clientID)
        }

        guard returnedClientID == nil || returnedClientID == attempt.clientID else {
            throw ChatGPTOAuthError.unexpectedClientID
        }
        return (code, attempt.clientID)
    }

    private func exchangeCode(
        _ code: String,
        clientID: String,
        attempt: ChatGPTAuthorizationAttempt
    ) async throws -> ChatGPTTokenResponse {
        var request = URLRequest(url: ChatGPTAuthConfiguration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = chatGPTFormBody([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": attempt.codeVerifier,
            "redirect_uri": attempt.redirectURI.absoluteString,
            "resource": ChatGPTAuthConfiguration.resource
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTOAuthError.exchangeFailed }
        guard (200..<300).contains(http.statusCode) else {
            if chatGPTOAuthErrorCode(in: data) == "invalid_grant" {
                throw ChatGPTOAuthError.invalidGrant(clientID: clientID)
            }
            throw ChatGPTOAuthError.exchangeFailed
        }
        return try Self.tokenResponse(from: data, requireIDToken: true)
    }

    nonisolated static func tokenResponse(from data: Data, requireIDToken: Bool) throws -> ChatGPTTokenResponse {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String, !accessToken.isEmpty,
              let refreshToken = object["refresh_token"] as? String, !refreshToken.isEmpty,
              let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue else {
            throw ChatGPTOAuthError.exchangeFailed
        }

        let idToken = object["id_token"] as? String
        if requireIDToken, (idToken?.isEmpty ?? true) {
            throw ChatGPTOAuthError.exchangeFailed
        }

        return ChatGPTTokenResponse(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresIn: expiresIn,
            scope: object["scope"] as? String,
            earliestRefreshAt: parseEarliestRefreshAt(object["earliest_refresh_at"])
        )
    }

    private func waitForCallbackAndBrowserCompletion(
        listener: LoopbackCallbackListener,
        authorizationURL: URL,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> URL {
        defer { listener.cancel() }
        return try await withThrowingTaskGroup(of: AuthorizationEvent.self) { group in
            group.addTask {
                .callback(try await listener.waitForCallback())
            }
            group.addTask { [weak self] in
                guard let self else { throw ChatGPTOAuthError.cancelled }
                return .browserCompleted(try await self.startWebAuthenticationSession(
                    url: authorizationURL,
                    presentationAnchor: presentationAnchor
                ))
            }
            defer { group.cancelAll() }

            guard let first = try await group.next() else { throw ChatGPTOAuthError.invalidCallback }
            switch first {
            case .callback(let callbackURL):
                guard let second = try await group.next(), case .browserCompleted(let completionURL) = second,
                      completionURL == ChatGPTAuthConfiguration.completionURL else {
                    throw ChatGPTOAuthError.invalidCallback
                }
                return callbackURL
            case .browserCompleted(let completionURL):
                guard completionURL == ChatGPTAuthConfiguration.completionURL,
                      let second = try await group.next(), case .callback(let callbackURL) = second else {
                    throw ChatGPTOAuthError.invalidCallback
                }
                return callbackURL
            }
        }
    }

    @MainActor
    private func startWebAuthenticationSession(
        url: URL,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: ChatGPTAuthConfiguration.completionScheme) { [weak self] callbackURL, error in
                    self?.clearAuthenticationSession()
                    if let error = error as? ASWebAuthenticationSessionError,
                       error.code == .canceledLogin {
                        continuation.resume(throwing: ChatGPTOAuthError.cancelled)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: ChatGPTOAuthError.invalidCallback)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                setAuthenticationSession(session, anchor: presentationAnchor)
                guard session.start() else {
                    clearAuthenticationSession()
                    continuation.resume(throwing: ChatGPTOAuthError.cancelled)
                    return
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelAuthenticationSession()
            }
        })
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        authenticationLock.lock()
        defer { authenticationLock.unlock() }
        return anchor ?? ASPresentationAnchor()
    }

    private func setAuthenticationSession(_ session: ASWebAuthenticationSession, anchor: ASPresentationAnchor) {
        authenticationLock.lock()
        self.authenticationSession = session
        self.anchor = anchor
        authenticationLock.unlock()
    }

    private func clearAuthenticationSession() {
        authenticationLock.lock()
        authenticationSession = nil
        anchor = nil
        authenticationLock.unlock()
    }

    private func cancelAuthenticationSession() {
        authenticationLock.lock()
        let session = authenticationSession
        authenticationLock.unlock()
        session?.cancel()
    }

    private nonisolated static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        precondition(SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess)
        return Data(bytes).base64URLEncodedString()
    }
}

func chatGPTFormBody(_ values: [String: String]) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))
    let body = values.map { key, value in
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(encodedKey)=\(encodedValue)"
    }
    .sorted()
    .joined(separator: "&")
    return Data(body.utf8)
}

func chatGPTOAuthErrorCode(in data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if let code = object["error"] as? String { return code }
    return (object["error"] as? [String: Any])?["code"] as? String
}

private func parseEarliestRefreshAt(_ value: Any?) -> Date? {
    if let number = value as? NSNumber {
        return Date(timeIntervalSince1970: number.doubleValue)
    }
    guard let string = value as? String else { return nil }
    if let seconds = TimeInterval(string) {
        return Date(timeIntervalSince1970: seconds)
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
