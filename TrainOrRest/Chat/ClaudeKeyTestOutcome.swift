import Foundation

/// What a Claude key check means for the user, so every failure can name its fix.
enum ClaudeKeyTestOutcome: Equatable {
    case connected
    /// 401/403: the key is wrong or revoked; the user needs a new one.
    case rejected
    /// 400 "credit balance is too low": the key works but the account has no prepaid credits.
    case needsCredits
    case rateLimited
    case offline
    case failed(String)

    static let keysURL = URL(string: "https://platform.claude.com/settings/keys")!
    static let billingURL = URL(string: "https://platform.claude.com/settings/billing")!
    static let keyPrefix = "sk-ant-"

    init(error: Error?) {
        guard let error else {
            self = .connected
            return
        }
        switch error as? ClaudeClientError {
        case .badKey:
            self = .rejected
        case .rateLimited:
            self = .rateLimited
        case .offline, .connectionLost, .timedOut:
            self = .offline
        case .api(let message) where message.localizedCaseInsensitiveContains("credit balance"):
            self = .needsCredits
        default:
            self = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The trimmed key when the pasted text looks like a Claude API key, else `nil`.
    static func claudeKey(fromPasted text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(keyPrefix), trimmed.count > keyPrefix.count else { return nil }
        return trimmed
    }
}
