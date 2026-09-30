import Combine
import Foundation

struct IntervalsAthlete: Codable, Equatable {
    var id: String
    var name: String?
}

enum IntervalsConnectionMethod: String, Codable, Equatable {
    case oauth
    case apiKey
}

struct IntervalsOAuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scope: String?
}

struct IntervalsConnection: Equatable {
    var method: IntervalsConnectionMethod
    var athlete: IntervalsAthlete
    private var authentication: IntervalsAuthentication
    var scope: String?

    init(method: IntervalsConnectionMethod, athlete: IntervalsAthlete, authentication: IntervalsAuthentication, scope: String? = nil) {
        self.method = method
        self.athlete = athlete
        self.authentication = authentication
        self.scope = scope
    }

    var credentials: IntervalsICUCredentials {
        IntervalsICUCredentials(athleteID: athlete.id, authentication: authentication)
    }
}

enum IntervalsConnectionState: Equatable {
    case disconnected
    case connected(IntervalsConnection)
    case needsReconnect(method: IntervalsConnectionMethod, athlete: IntervalsAthlete?)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var method: IntervalsConnectionMethod? {
        switch self {
        case .disconnected: nil
        case .connected(let connection): connection.method
        case .needsReconnect(let method, _): method
        }
    }

    var athlete: IntervalsAthlete? {
        switch self {
        case .disconnected: nil
        case .connected(let connection): connection.athlete
        case .needsReconnect(_, let athlete): athlete
        }
    }
}

enum IntervalsConnectionStoreError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        "intervals.icu is not connected."
    }
}

enum IntervalsConnectionStorage {
    static let authMethodKey = "intervalsICUAuthMethod"
    static let needsReconnectKey = "intervalsICUNeedsReconnect"
    static let athleteNameKey = "intervalsICUAthleteName"
}

enum IntervalsConnectionResolver {
    static func state(
        userDefaults: UserDefaults = .standard,
        loadSecret: (String) throws -> String? = { try KeychainStore.load(account: $0) },
        now: Date = .now
    ) -> IntervalsConnectionState {
        let athlete = IntervalsAthlete(
            id: userDefaults.string(forKey: WorkoutPushSettings.athleteIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            name: userDefaults.string(forKey: IntervalsConnectionStorage.athleteNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let selectedMethod = userDefaults.string(forKey: IntervalsConnectionStorage.authMethodKey)
            .flatMap(IntervalsConnectionMethod.init(rawValue:))

        if selectedMethod == .oauth {
            guard !athlete.id.isEmpty,
                  let tokens = oauthTokens(loadSecret: loadSecret) else {
                return .needsReconnect(method: .oauth, athlete: athlete.id.isEmpty ? nil : athlete)
            }
            if userDefaults.bool(forKey: IntervalsConnectionStorage.needsReconnectKey)
                || (tokens.expiresAt?.addingTimeInterval(-60) ?? .distantFuture) <= now {
                return .needsReconnect(method: .oauth, athlete: athlete)
            }
            return .connected(IntervalsConnection(
                method: .oauth,
                athlete: athlete,
                authentication: .oauth(accessToken: tokens.accessToken),
                scope: tokens.scope
            ))
        }

        guard !athlete.id.isEmpty,
              let apiKey = try? loadSecret(KeychainStore.intervalsICUAccount),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .disconnected
        }
        return .connected(IntervalsConnection(
            method: .apiKey,
            athlete: athlete,
            authentication: .apiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        ))
    }

    private static func oauthTokens(loadSecret: (String) throws -> String?) -> IntervalsOAuthTokens? {
        guard let encoded = try? loadSecret(KeychainStore.intervalsICUOAuthTokenAccount),
              let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(IntervalsOAuthTokens.self, from: data)
    }
}

@MainActor
final class IntervalsConnectionStore: ObservableObject {
    @Published private(set) var state: IntervalsConnectionState

    private let userDefaults: UserDefaults
    private let loadSecret: (String) throws -> String?
    private let saveSecret: (String, String) throws -> Void
    private let deleteSecret: (String) throws -> Void

    init(
        userDefaults: UserDefaults = .standard,
        loadSecret: @escaping (String) throws -> String? = { try KeychainStore.load(account: $0) },
        saveSecret: @escaping (String, String) throws -> Void = { value, account in try KeychainStore.save(value, account: account) },
        deleteSecret: @escaping (String) throws -> Void = { try KeychainStore.delete(account: $0) }
    ) {
        self.userDefaults = userDefaults
        self.loadSecret = loadSecret
        self.saveSecret = saveSecret
        self.deleteSecret = deleteSecret
        state = IntervalsConnectionResolver.state(userDefaults: userDefaults, loadSecret: loadSecret)
    }

    var oauthAvailable: Bool {
        IntervalsOAuthConfiguration.current != nil
    }

    func reload() {
        state = IntervalsConnectionResolver.state(userDefaults: userDefaults, loadSecret: loadSecret)
    }

    func credentials() throws -> IntervalsICUCredentials {
        guard case .connected(let connection) = state else {
            throw IntervalsConnectionStoreError.notConnected
        }
        return connection.credentials
    }

    func saveOAuth(_ callback: IntervalsOAuthCallback) throws {
        let tokens = IntervalsOAuthTokens(
            accessToken: callback.accessToken,
            refreshToken: callback.refreshToken,
            expiresAt: callback.expiresIn.map { Date.now.addingTimeInterval($0) },
            scope: callback.scope
        )
        let encoded = Data(try JSONEncoder().encode(tokens)).base64EncodedString()
        try saveSecret(encoded, KeychainStore.intervalsICUOAuthTokenAccount)
        userDefaults.set(callback.athleteID, forKey: WorkoutPushSettings.athleteIDKey)
        if let athleteName = callback.athleteName?.trimmingCharacters(in: .whitespacesAndNewlines), !athleteName.isEmpty {
            userDefaults.set(athleteName, forKey: IntervalsConnectionStorage.athleteNameKey)
        } else {
            userDefaults.removeObject(forKey: IntervalsConnectionStorage.athleteNameKey)
        }
        userDefaults.set(IntervalsConnectionMethod.oauth.rawValue, forKey: IntervalsConnectionStorage.authMethodKey)
        userDefaults.set(true, forKey: IntervalsConnectionStorage.needsReconnectKey)
        reload()
    }

    func markOAuthValidated() {
        guard state.method == .oauth else { return }
        userDefaults.set(false, forKey: IntervalsConnectionStorage.needsReconnectKey)
        reload()
    }

    func markNeedsReconnectIfOAuth() {
        guard state.method == .oauth else { return }
        userDefaults.set(true, forKey: IntervalsConnectionStorage.needsReconnectKey)
        reload()
    }

    func saveAPIKey(athleteID: String, apiKey: String) throws {
        let trimmedAthleteID = athleteID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAthleteID.isEmpty, !trimmedAPIKey.isEmpty else {
            throw IntervalsConnectionStoreError.notConnected
        }
        try saveSecret(trimmedAPIKey, KeychainStore.intervalsICUAccount)
        userDefaults.set(trimmedAthleteID, forKey: WorkoutPushSettings.athleteIDKey)
        userDefaults.set(IntervalsConnectionMethod.apiKey.rawValue, forKey: IntervalsConnectionStorage.authMethodKey)
        userDefaults.set(false, forKey: IntervalsConnectionStorage.needsReconnectKey)
        reload()
    }

    func disconnect() {
        try? deleteSecret(KeychainStore.intervalsICUOAuthTokenAccount)
        try? deleteSecret(KeychainStore.intervalsICUAccount)
        userDefaults.removeObject(forKey: WorkoutPushSettings.athleteIDKey)
        userDefaults.removeObject(forKey: IntervalsConnectionStorage.athleteNameKey)
        userDefaults.removeObject(forKey: IntervalsConnectionStorage.authMethodKey)
        userDefaults.removeObject(forKey: IntervalsConnectionStorage.needsReconnectKey)
        reload()
    }
}
