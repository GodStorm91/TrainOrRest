import Combine
import Foundation

enum GrokConnectionState: Equatable {
    case signedOut
    case authorizing(userCode: String, verificationURL: URL)
    case connected(email: String?)
    case needsReconnect
}

protocol GrokTokenProviding: Sendable {
    func accessToken() async throws -> String
    func refreshAfterUnauthorized() async throws -> String
}

struct GrokCredentialRecord: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: Date
    var email: String?
    var subject: String?
}

private final class GrokStateSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private let subject: CurrentValueSubject<GrokConnectionState, Never>
    private var currentState: GrokConnectionState

    init(state: GrokConnectionState) {
        subject = CurrentValueSubject(state)
        currentState = state
    }

    var state: GrokConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return currentState
    }

    var publisher: AnyPublisher<GrokConnectionState, Never> {
        subject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    func update(_ state: GrokConnectionState) {
        lock.lock()
        currentState = state
        lock.unlock()
        subject.send(state)
    }
}

actor GrokTokenStore: GrokTokenProviding {
    static let shared = GrokTokenStore()

    private nonisolated let stateSnapshot: GrokStateSnapshot
    private let oauth: GrokOAuthService
    private let now: @Sendable () -> Date
    private var credential: GrokCredentialRecord?
    private var refreshTask: Task<GrokCredentialRecord, Error>?
    private var tokenEndpoint: URL?
    private var signInGeneration = 0

    init(oauth: GrokOAuthService = GrokOAuthService(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.oauth = oauth
        self.now = now
        let stored = Self.loadCredential()
        credential = stored
        stateSnapshot = GrokStateSnapshot(state: stored == nil ? .signedOut : .connected(email: stored?.email))
    }

    nonisolated var state: GrokConnectionState { stateSnapshot.state }
    nonisolated var statePublisher: AnyPublisher<GrokConnectionState, Never> { stateSnapshot.publisher }

    func signIn(onAuthorization: @escaping @Sendable (GrokDeviceAuthorization) -> Void) async throws {
        signInGeneration += 1
        let generation = signInGeneration
        let authorization = try await oauth.startDeviceAuthorization()
        guard generation == signInGeneration else { throw GrokOAuthError.cancelled }
        stateSnapshot.update(.authorizing(userCode: authorization.userCode, verificationURL: authorization.verificationURL))
        onAuthorization(authorization)
        do {
            let endpoint = try await currentTokenEndpoint()
            let tokens = try await oauth.pollUntilComplete(authorization, tokenEndpoint: endpoint)
            guard generation == signInGeneration else { throw GrokOAuthError.cancelled }
            let identity = await oauth.identity(accessToken: tokens.accessToken)
            let record = GrokCredentialRecord(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                accessTokenExpiresAt: tokens.expiresAt,
                email: identity?.email,
                subject: identity?.subject
            )
            try save(record)
            credential = record
            stateSnapshot.update(.connected(email: record.email))
        } catch {
            if generation == signInGeneration, credential == nil {
                stateSnapshot.update(.signedOut)
            }
            throw error
        }
    }

    func cancelSignIn() {
        signInGeneration += 1
        if case .authorizing = stateSnapshot.state {
            stateSnapshot.update(credential == nil ? .signedOut : .connected(email: credential?.email))
        }
    }

    func signOut() {
        signInGeneration += 1
        credential = nil
        tokenEndpoint = nil
        refreshTask?.cancel()
        refreshTask = nil
        try? KeychainStore.delete(account: KeychainStore.grokCredentialAccount)
        stateSnapshot.update(.signedOut)
    }

    func accessToken() async throws -> String {
        guard var record = credential else {
            stateSnapshot.update(.needsReconnect)
            throw ClaudeClientError.api("Your Grok session ended. Sign in again in Settings; your chats are safe.")
        }
        if record.accessTokenExpiresAt.timeIntervalSince(now()) > 60 {
            return record.accessToken
        }
        record = try await refreshed(record)
        return record.accessToken
    }

    func refreshAfterUnauthorized() async throws -> String {
        guard let record = credential else {
            stateSnapshot.update(.needsReconnect)
            throw ClaudeClientError.api("Your Grok session ended. Sign in again in Settings; your chats are safe.")
        }
        return try await refreshed(record, force: true).accessToken
    }
    private func refreshed(_ record: GrokCredentialRecord, force: Bool = false) async throws -> GrokCredentialRecord {
        if !force, record.accessTokenExpiresAt.timeIntervalSince(now()) > 60 {
            return record
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task<GrokCredentialRecord, Error> {
            let endpoint = try await currentTokenEndpoint()
            let tokens = try await oauth.refresh(refreshToken: record.refreshToken, tokenEndpoint: endpoint)
            return GrokCredentialRecord(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                accessTokenExpiresAt: tokens.expiresAt,
                email: record.email,
                subject: record.subject
            )
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let updated = try await task.value
            try save(updated)
            credential = updated
            stateSnapshot.update(.connected(email: updated.email))
            return updated
        } catch let error as GrokOAuthError where Self.isTerminal(error) {
            credential = nil
            try? KeychainStore.delete(account: KeychainStore.grokCredentialAccount)
            stateSnapshot.update(.needsReconnect)
            throw ClaudeClientError.api("Your Grok session ended. Sign in again in Settings; your chats are safe.")
        } catch {
            throw error
        }
    }

    private func currentTokenEndpoint() async throws -> URL {
        if let tokenEndpoint { return tokenEndpoint }
        let endpoint = try await oauth.discoverTokenEndpoint()
        tokenEndpoint = endpoint
        return endpoint
    }

    private func save(_ record: GrokCredentialRecord) throws {
        let data = try JSONEncoder().encode(record)
        guard let json = String(data: data, encoding: .utf8) else { throw GrokOAuthError.invalidResponse }
        try KeychainStore.save(json, account: KeychainStore.grokCredentialAccount)
    }

    private static func loadCredential() -> GrokCredentialRecord? {
        guard let json = try? KeychainStore.load(account: KeychainStore.grokCredentialAccount),
              let data = json.data(using: .utf8),
              let record = try? JSONDecoder().decode(GrokCredentialRecord.self, from: data),
              !record.accessToken.isEmpty,
              !record.refreshToken.isEmpty else {
            return nil
        }
        return record
    }
    private static func isTerminal(_ error: GrokOAuthError) -> Bool {
        switch error {
        case .expired, .declined:
            return true
        case .http(_, let code):
            return ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired"].contains(code)
        case .cancelled, .invalidResponse, .endpointRejected, .transport:
            return false
        }
    }
}
