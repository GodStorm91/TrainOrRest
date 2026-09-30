import Foundation
import Security

enum KeychainStore {
    static let apiKeyAccount = "anthropic-api-key"
    static let openAIAPIKeyAccount = "openai-api-key"
    static let intervalsICUAccount = "intervals-icu-api-key"
    static let intervalsICUOAuthTokenAccount = "intervals-icu-oauth-token-v1"
    static let chatGPTCredentialAccount = "chatgpt-credential-v1"
    static let chatGPTHostIDAccount = "chatgpt-host-id"
    static let grokCredentialAccount = "grok-credential-v1"

    enum StoreError: Error {
        case unexpectedStatus(OSStatus)
    }

    static func save(_ value: String, account: String = apiKeyAccount) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw StoreError.unexpectedStatus(updateStatus) }
        } else if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.unexpectedStatus(addStatus) }
        } else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    static func load(account: String = apiKeyAccount) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String = apiKeyAccount) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "TrainOrRest",
            kSecAttrAccount as String: account
        ]
    }
}
