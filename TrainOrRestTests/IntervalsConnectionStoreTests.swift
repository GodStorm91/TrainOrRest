import XCTest
@testable import TrainOrRest

@MainActor
final class IntervalsConnectionStoreTests: XCTestCase {
    func testLegacyAPIKeyRemainsConnectedWithoutAnAuthMethod() throws {
        let defaults = try makeDefaults()
        defaults.set("i636286", forKey: WorkoutPushSettings.athleteIDKey)
        let secrets = SecretStore([KeychainStore.intervalsICUAccount: "legacy-key"])

        let state = IntervalsConnectionResolver.state(
            userDefaults: defaults,
            loadSecret: { secrets.value(for: $0) }
        )

        guard case .connected(let connection) = state else {
            return XCTFail("Expected migrated API-key connection")
        }
        XCTAssertEqual(connection.method, .apiKey)
        XCTAssertEqual(connection.credentials.authentication, .apiKey("legacy-key"))
    }

    func testOAuthConnectionNeedsValidationThenUsesBearerCredentials() throws {
        let defaults = try makeDefaults()
        let secrets = SecretStore()
        let store = IntervalsConnectionStore(
            userDefaults: defaults,
            loadSecret: { secrets.value(for: $0) },
            saveSecret: { secrets.save($0, account: $1) },
            deleteSecret: { secrets.delete(account: $0) }
        )

        try store.saveOAuth(IntervalsOAuthCallback(
            accessToken: "access-token",
            athleteID: "i636286",
            athleteName: "Ada",
            scope: "CALENDAR:WRITE,ACTIVITY:READ",
            refreshToken: nil,
            expiresIn: 3600
        ))
        XCTAssertEqual(store.state.method, .oauth)
        XCTAssertFalse(store.state.isConnected)

        store.markOAuthValidated()

        XCTAssertEqual(try store.credentials().authentication, .oauth(accessToken: "access-token"))
        XCTAssertEqual(store.state.athlete?.name, "Ada")
    }

    func testUnauthorizedOAuthConnectionRequiresReconnect() throws {
        let store = try validatedOAuthStore()

        store.markNeedsReconnectIfOAuth()

        guard case .needsReconnect(let method, let athlete) = store.state else {
            return XCTFail("Expected reconnect state")
        }
        XCTAssertEqual(method, .oauth)
        XCTAssertEqual(athlete?.id, "i636286")
    }

    func testDisconnectClearsOAuthAndLegacyCredentials() throws {
        let defaults = try makeDefaults()
        let secrets = SecretStore([
            KeychainStore.intervalsICUAccount: "legacy-key",
            KeychainStore.intervalsICUOAuthTokenAccount: "oauth-token",
        ])
        defaults.set("i636286", forKey: WorkoutPushSettings.athleteIDKey)
        defaults.set(IntervalsConnectionMethod.oauth.rawValue, forKey: IntervalsConnectionStorage.authMethodKey)
        let store = IntervalsConnectionStore(
            userDefaults: defaults,
            loadSecret: { secrets.value(for: $0) },
            saveSecret: { secrets.save($0, account: $1) },
            deleteSecret: { secrets.delete(account: $0) }
        )

        store.disconnect()

        XCTAssertEqual(store.state, .disconnected)
        XCTAssertNil(secrets.value(for: KeychainStore.intervalsICUAccount))
        XCTAssertNil(secrets.value(for: KeychainStore.intervalsICUOAuthTokenAccount))
        XCTAssertNil(defaults.string(forKey: WorkoutPushSettings.athleteIDKey))
    }

    private func validatedOAuthStore() throws -> IntervalsConnectionStore {
        let defaults = try makeDefaults()
        let secrets = SecretStore()
        let store = IntervalsConnectionStore(
            userDefaults: defaults,
            loadSecret: { secrets.value(for: $0) },
            saveSecret: { secrets.save($0, account: $1) },
            deleteSecret: { secrets.delete(account: $0) }
        )
        try store.saveOAuth(IntervalsOAuthCallback(
            accessToken: "access-token",
            athleteID: "i636286",
            athleteName: nil,
            scope: nil,
            refreshToken: nil,
            expiresIn: 3600
        ))
        store.markOAuthValidated()
        return store
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "IntervalsConnectionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class SecretStore {
    private var values: [String: String]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func value(for account: String) -> String? {
        values[account]
    }

    func save(_ value: String, account: String) {
        values[account] = value
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }
}
