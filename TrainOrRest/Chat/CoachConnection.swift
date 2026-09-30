import Foundation

/// How the coach reaches a model provider. Stored per install; each connection
/// keeps its own selected model so switching back restores the previous pick.
enum CoachConnection: String, CaseIterable, Codable {
    /// ChatGPT plan via Sign in with ChatGPT.
    case chatGPT
    /// Anthropic API key.
    case anthropicKey
    /// OpenAI API key (Chat Completions).
    case openAIKey

    static let storageKey = "coachConnection"

    var modelStorageKey: String { "coachModel.\(rawValue)" }

    /// `nil` for `.chatGPT`: its models come from the account's `/v1/models` catalog.
    var defaultModel: String? {
        switch self {
        case .chatGPT: nil
        case .anthropicKey: CoachChatConfig.defaultModel
        case .openAIKey: CoachChatConfig.defaultOpenAIModel
        }
    }

    var displayName: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .anthropicKey: "Claude"
        case .openAIKey: "OpenAI"
        }
    }

    /// Keychain account holding the API key, `nil` for token-based connections.
    var apiKeyAccount: String? {
        switch self {
        case .chatGPT: nil
        case .anthropicKey: KeychainStore.apiKeyAccount
        case .openAIKey: KeychainStore.openAIAPIKeyAccount
        }
    }
}

enum CoachCredential {
    case apiKey(String)
    case chatGPT(ChatGPTTokenProviding)
}

protocol ChatGPTTokenProviding: Sendable {
    /// A valid access token, refreshed first when it is near expiry.
    func accessToken() async throws -> String
    /// Forces a refresh after the API rejected the current access token.
    func refreshAfterUnauthorized() async throws -> String
    /// Moves the connection into the state implied by a ChatGPT plan error
    /// (`planUsageLimit`, `planNotEligible`, `needsReconnect`). Other errors are ignored.
    func recordPlanError(_ error: ClaudeClientError) async
}

/// The connection a turn runs on plus the credential that authorizes it.
struct CoachAccess {
    let connection: CoachConnection
    let credential: CoachCredential
}

struct CoachSelection: Equatable {
    let connection: CoachConnection
    let model: String
}

enum CoachCredentialResolver {
    static let legacyModelKey = "coachModel"

    static func current(_ defaults: UserDefaults = .standard) -> CoachSelection {
        let connection = defaults.string(forKey: CoachConnection.storageKey)
            .flatMap(CoachConnection.init(rawValue:)) ?? .chatGPT
        return CoachSelection(connection: connection, model: model(for: connection, defaults: defaults))
    }

    /// The selected model for a connection. Empty for `.chatGPT` until the catalog picked one;
    /// the ChatGPT client resolves an empty model against the account catalog.
    static func model(for connection: CoachConnection, defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: connection.modelStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? (connection.defaultModel ?? "") : stored
    }

    /// `nil` means the connection is not usable right now.
    static func credential(for connection: CoachConnection) -> CoachCredential? {
        switch connection {
        case .chatGPT:
            guard case .connected = ChatGPTTokenStore.shared.state else { return nil }
            return .chatGPT(ChatGPTTokenStore.shared)
        case .anthropicKey, .openAIKey:
            guard let account = connection.apiKeyAccount,
                  let key = storedKey(account: account) else { return nil }
            return .apiKey(key)
        }
    }

    static func isConnected(_ connection: CoachConnection) -> Bool {
        credential(for: connection) != nil
    }

    static func access(for connection: CoachConnection) -> CoachAccess? {
        credential(for: connection).map { CoachAccess(connection: connection, credential: $0) }
    }

    /// Existing installs keep the provider they already used; fresh installs start on ChatGPT.
    /// Legacy installs derived the provider from the model prefix, defaulting to Claude.
    static func migrateIfNeeded(
        _ defaults: UserDefaults = .standard,
        hasStoredKey: (String) -> Bool = { storedKey(account: $0) != nil }
    ) {
        guard defaults.string(forKey: CoachConnection.storageKey) == nil else { return }
        let legacyModel = defaults.string(forKey: legacyModelKey)
        let isExistingInstall = legacyModel != nil
            || hasStoredKey(KeychainStore.apiKeyAccount)
            || hasStoredKey(KeychainStore.openAIAPIKeyAccount)

        let connection: CoachConnection
        if isExistingInstall {
            let model = legacyModel ?? CoachChatConfig.defaultModel
            connection = isLegacyOpenAIModel(model) ? .openAIKey : .anthropicKey
            if let legacyModel {
                defaults.set(legacyModel, forKey: connection.modelStorageKey)
            }
        } else {
            connection = .chatGPT
        }
        defaults.set(connection.rawValue, forKey: CoachConnection.storageKey)
        defaults.removeObject(forKey: legacyModelKey)
    }

    private static func isLegacyOpenAIModel(_ model: String) -> Bool {
        model.hasPrefix("gpt-") || model.hasPrefix("o")
    }

    private static func storedKey(account: String) -> String? {
        let key = ((try? KeychainStore.load(account: account)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}

enum CoachClientRouter {
    static func client(
        for connection: CoachConnection,
        anthropicClient: ClaudeServicing,
        openAIClient: ClaudeServicing,
        chatGPTClient: ClaudeServicing
    ) -> ClaudeServicing {
        switch connection {
        case .chatGPT: chatGPTClient
        case .anthropicKey: anthropicClient
        case .openAIKey: openAIClient
        }
    }
}
