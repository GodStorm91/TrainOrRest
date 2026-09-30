import AuthenticationServices
import Combine
import Foundation

/// The state is derived from the persisted credential except for server-reported
/// plan conditions, which intentionally remain in memory only.
enum ChatGPTConnectionState: Equatable {
    case signedOut
    case connected(email: String?)
    case planUsageDisabled
    case needsReconnect
    case usageLimited(until: Date?)
    case notEligible
}

struct ChatGPTCredentialRecord: Codable, Sendable, Equatable {
    var issuer: String
    var subject: String
    var email: String?
    var clientID: String
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: Date
    var earliestRefreshAt: Date?
    var scopes: Set<String>

    var hasTokens: Bool {
        !accessToken.isEmpty && !refreshToken.isEmpty
    }

    mutating func clearTokens() {
        idToken = ""
        accessToken = ""
        refreshToken = ""
        earliestRefreshAt = nil
        accessTokenExpiresAt = .distantPast
    }
}

protocol ChatGPTKeychainStoring: Sendable {
    func load(account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func delete(account: String) throws
}

struct LiveChatGPTKeychainStore: ChatGPTKeychainStoring {
    func load(account: String) throws -> String? {
        try KeychainStore.load(account: account)
    }

    func save(_ value: String, account: String) throws {
        try KeychainStore.save(value, account: account)
    }

    func delete(account: String) throws {
        try KeychainStore.delete(account: account)
    }
}

private final class ChatGPTStateSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private let subject: CurrentValueSubject<ChatGPTConnectionState, Never>
    private var currentState: ChatGPTConnectionState
    private var currentEmail: String?

    init(state: ChatGPTConnectionState, email: String?) {
        subject = CurrentValueSubject(state)
        currentState = state
        currentEmail = email
    }

    var state: ChatGPTConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    var email: String? {
        lock.lock()
        defer { lock.unlock() }
        return currentEmail
    }

    var publisher: AnyPublisher<ChatGPTConnectionState, Never> {
        subject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func update(state: ChatGPTConnectionState, email: String?) {
        lock.lock()
        currentState = state
        currentEmail = email
        lock.unlock()
        subject.send(state)
    }
}

actor ChatGPTTokenStore: ChatGPTTokenProviding {
    static let shared = ChatGPTTokenStore()

    private nonisolated let stateSnapshot: ChatGPTStateSnapshot
    private let keychain: any ChatGPTKeychainStoring
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let oauthService: any ChatGPTOAuthServicing
    private let idTokenValidator: any ChatGPTIDTokenValidating
    private var credential: ChatGPTCredentialRecord?
    private var refreshTask: Task<String, Error>?
    private var credentialGeneration = 0

    init(
        keychain: any ChatGPTKeychainStoring = LiveChatGPTKeychainStore(),
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
        oauthService: any ChatGPTOAuthServicing = ChatGPTOAuthService(),
        idTokenValidator: any ChatGPTIDTokenValidating = IDTokenValidator()
    ) {
        self.keychain = keychain
        self.session = session
        self.now = now
        self.oauthService = oauthService
        self.idTokenValidator = idTokenValidator

        let credential = Self.loadCredential(from: keychain)
        self.credential = credential
        self.stateSnapshot = ChatGPTStateSnapshot(
            state: Self.derivedState(from: credential),
            email: credential?.email
        )
    }

    /// Synchronous snapshot for view code and `CoachCredentialResolver`.
    nonisolated var state: ChatGPTConnectionState { stateSnapshot.state }

    nonisolated var statePublisher: AnyPublisher<ChatGPTConnectionState, Never> { stateSnapshot.publisher }

    /// Email of the stored account, when known.
    nonisolated var email: String? { stateSnapshot.email }

    #if DEBUG
    /// DevSeed screenshots only: shows a state without a stored credential.
    nonisolated func debugOverrideState(_ state: ChatGPTConnectionState) {
        let email: String? = if case .connected(let email) = state { email } else { nil }
        stateSnapshot.update(state: state, email: email)
    }
    #endif

    /// New registration or reauthorization. `requestConsent` re-asks for plan-usage consent.
    func signIn(presentationAnchor: ASPresentationAnchor, requestConsent: Bool = false) async throws {
        let hostID = try hostID()
        let existingCredential = credential
        let existingRegistration = existingCredential.map {
            ChatGPTExistingRegistration(
                clientID: $0.clientID,
                idTokenHint: $0.idToken.isEmpty ? nil : $0.idToken,
                loginHint: $0.email
            )
        }

        let authorization: ChatGPTAuthorizationResult
        do {
            authorization = try await authorizeOnce(
                presentationAnchor: presentationAnchor,
                hostID: hostID,
                existingRegistration: existingRegistration,
                requestConsent: requestConsent
            )
        } catch ChatGPTOAuthError.declined {
            stateSnapshot.update(
                state: existingCredential == nil ? .signedOut : .planUsageDisabled,
                email: existingCredential?.email
            )
            throw ChatGPTOAuthError.declined
        }

        guard authorization.clientID != ChatGPTAuthConfiguration.registrationClientID else {
            throw ChatGPTOAuthError.incompleteRegistration
        }
        guard let idToken = authorization.tokenResponse.idToken, !idToken.isEmpty else {
            throw ChatGPTOAuthError.exchangeFailed
        }

        let claims = try await idTokenValidator.validate(
            idToken: idToken,
            clientID: authorization.clientID,
            nonce: authorization.nonce,
            expectedSubject: existingCredential?.subject
        )
        let scopes = authorization.tokenResponse.scopes
        let updated = ChatGPTCredentialRecord(
            issuer: ChatGPTAuthConfiguration.issuer,
            subject: claims.subject,
            email: claims.email,
            clientID: authorization.clientID,
            idToken: idToken,
            accessToken: authorization.tokenResponse.accessToken,
            refreshToken: authorization.tokenResponse.refreshToken,
            accessTokenExpiresAt: now().addingTimeInterval(authorization.tokenResponse.expiresIn),
            earliestRefreshAt: authorization.tokenResponse.earliestRefreshAt,
            scopes: scopes
        )

        // A single Keychain replacement keeps rotated credentials from being observed piecemeal.
        try persist(updated)
        credential = updated
        credentialGeneration += 1
        updateStateFromCredential()
    }

    func accessToken() async throws -> String {
        try ensureSessionIsUsable()
        guard let credential else { throw ClaudeClientError.needsReconnect }

        let currentTime = now()
        if credential.accessTokenExpiresAt > currentTime.addingTimeInterval(5 * 60) {
            return credential.accessToken
        }
        if let earliestRefreshAt = credential.earliestRefreshAt,
           earliestRefreshAt > currentTime {
            if credential.accessTokenExpiresAt > currentTime {
                return credential.accessToken
            }
            throw ClaudeClientError.api("ChatGPT access token cannot be refreshed yet.")
        }
        return try await refresh(force: false)
    }

    func refreshAfterUnauthorized() async throws -> String {
        try ensureSessionIsUsable()
        return try await refresh(force: true)
    }

    func recordPlanError(_ error: ClaudeClientError) async {
        switch error {
        case .planUsageLimit:
            stateSnapshot.update(state: .usageLimited(until: nil), email: credential?.email)
        case .planNotEligible:
            stateSnapshot.update(state: .notEligible, email: credential?.email)
        case .needsReconnect:
            clearTokensForReconnect()
        default:
            break
        }
    }

    /// Ends the in-memory usage-limit pause so the user can try again.
    func clearUsageLimit() {
        updateStateFromCredential()
    }

    /// Revokes, then clears tokens. Returns whether remote revocation was confirmed.
    @discardableResult
    func signOut() async -> Bool {
        refreshTask?.cancel()
        refreshTask = nil
        credentialGeneration += 1

        guard let current = credential else {
            stateSnapshot.update(state: .signedOut, email: nil)
            return false
        }

        let revoked = await revoke(refreshToken: current.refreshToken, clientID: current.clientID)
        var cleared = current
        cleared.clearTokens()
        try? persist(cleared)
        credential = cleared
        stateSnapshot.update(state: .signedOut, email: cleared.email)
        return revoked
    }

    private func authorizeOnce(
        presentationAnchor: ASPresentationAnchor,
        hostID: String,
        existingRegistration: ChatGPTExistingRegistration?,
        requestConsent: Bool
    ) async throws -> ChatGPTAuthorizationResult {
        do {
            return try await oauthService.authorize(
                presentationAnchor: presentationAnchor,
                hostID: hostID,
                existingRegistration: existingRegistration,
                requestConsent: requestConsent
            )
        } catch ChatGPTOAuthError.invalidGrant(let clientID) {
            let retryRegistration = ChatGPTExistingRegistration(
                clientID: clientID,
                idTokenHint: existingRegistration?.idTokenHint,
                loginHint: existingRegistration?.loginHint
            )
            return try await oauthService.authorize(
                presentationAnchor: presentationAnchor,
                hostID: hostID,
                existingRegistration: retryRegistration,
                requestConsent: requestConsent
            )
        }
    }

    private func ensureSessionIsUsable() throws {
        switch stateSnapshot.state {
        case .signedOut, .needsReconnect:
            throw ClaudeClientError.needsReconnect
        case .connected, .planUsageDisabled, .usageLimited, .notEligible:
            break
        }
        guard credential?.hasTokens == true else { throw ClaudeClientError.needsReconnect }
    }

    private func refresh(force: Bool) async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }

        guard let credential else { throw ClaudeClientError.needsReconnect }
        if !force,
           let earliestRefreshAt = credential.earliestRefreshAt,
           earliestRefreshAt > now() {
            if credential.accessTokenExpiresAt > now() {
                return credential.accessToken
            }
            throw ClaudeClientError.api("ChatGPT access token cannot be refreshed yet.")
        }

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw ClaudeClientError.needsReconnect }
            return try await self.performRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let current = credential, current.hasTokens else {
            throw ClaudeClientError.needsReconnect
        }
        let generation = credentialGeneration

        var request = URLRequest(url: ChatGPTAuthConfiguration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = chatGPTFormBody([
            "grant_type": "refresh_token",
            "client_id": current.clientID,
            "refresh_token": current.refreshToken,
            "resource": ChatGPTAuthConfiguration.resource
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.clientError(for: error)
        }

        guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let code = chatGPTOAuthErrorCode(in: data)
            if Self.terminalRefreshErrorCodes.contains(code ?? "") {
                clearTokensForReconnect()
                throw ClaudeClientError.needsReconnect
            }
            if code == "invalid_client" {
                throw ClaudeClientError.api("ChatGPT sign-in configuration error (invalid_client).")
            }
            throw ClaudeClientError.api("ChatGPT token refresh failed (HTTP \(http.statusCode)).")
        }

        let tokenResponse: ChatGPTTokenResponse
        do {
            tokenResponse = try ChatGPTOAuthService.tokenResponse(from: data, requireIDToken: false)
        } catch {
            throw ClaudeClientError.invalidResponse
        }
        guard generation == credentialGeneration else { throw CancellationError() }

        var updated = current
        updated.accessToken = tokenResponse.accessToken
        updated.refreshToken = tokenResponse.refreshToken
        if let idToken = tokenResponse.idToken, !idToken.isEmpty {
            updated.idToken = idToken
        }
        updated.accessTokenExpiresAt = now().addingTimeInterval(tokenResponse.expiresIn)
        updated.earliestRefreshAt = tokenResponse.earliestRefreshAt
        if let scope = tokenResponse.scope {
            updated.scopes = Set(scope.split(separator: " ").map(String.init))
        }

        // Persist before exposing the token so a rotated refresh token survives a crash.
        try persist(updated)
        credential = updated
        updateStateFromCredential()
        return updated.accessToken
    }

    private func revoke(refreshToken: String, clientID: String) async -> Bool {
        guard !refreshToken.isEmpty else { return false }
        for attempt in 0...2 {
            var request = URLRequest(url: ChatGPTAuthConfiguration.revocationEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = chatGPTFormBody([
                "token": refreshToken,
                "token_type_hint": "refresh_token",
                "client_id": clientID
            ])

            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return false }
                if (200..<300).contains(http.statusCode) { return true }
                guard http.statusCode >= 500, attempt < 2 else { return false }
            } catch is URLError {
                guard attempt < 2 else { return false }
            } catch {
                return false
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func clearTokensForReconnect() {
        guard var credential else {
            stateSnapshot.update(state: .needsReconnect, email: nil)
            return
        }
        credential.clearTokens()
        try? persist(credential)
        self.credential = credential
        credentialGeneration += 1
        stateSnapshot.update(state: .needsReconnect, email: credential.email)
    }

    private func hostID() throws -> String {
        if let hostID = try keychain.load(account: KeychainStore.chatGPTHostIDAccount), !hostID.isEmpty {
            return hostID
        }
        let hostID = "urn:uuid:\(UUID().uuidString.lowercased())"
        try keychain.save(hostID, account: KeychainStore.chatGPTHostIDAccount)
        return hostID
    }

    private func persist(_ credential: ChatGPTCredentialRecord) throws {
        let data = try JSONEncoder().encode(credential)
        try keychain.save(String(decoding: data, as: UTF8.self), account: KeychainStore.chatGPTCredentialAccount)
    }

    private func updateStateFromCredential() {
        stateSnapshot.update(state: Self.derivedState(from: credential), email: credential?.email)
    }

    private static func derivedState(from credential: ChatGPTCredentialRecord?) -> ChatGPTConnectionState {
        guard let credential else { return .signedOut }
        guard credential.hasTokens else { return .needsReconnect }
        return credential.scopes.contains(ChatGPTAuthConfiguration.planScope)
            ? .connected(email: credential.email)
            : .planUsageDisabled
    }

    private static func loadCredential(from keychain: any ChatGPTKeychainStoring) -> ChatGPTCredentialRecord? {
        guard let encoded = try? keychain.load(account: KeychainStore.chatGPTCredentialAccount),
              let data = encoded.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ChatGPTCredentialRecord.self, from: data)
    }

    private static let terminalRefreshErrorCodes: Set<String> = [
        "invalid_grant",
        "invalid_refresh_token",
        "token_expired",
        "refresh_token_expired",
        "refresh_token_invalidated",
        "refresh_token_reused"
    ]

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
}
