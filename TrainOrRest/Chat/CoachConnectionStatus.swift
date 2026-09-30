import Foundation

/// What the coach status card shows for the selected connection. Pure so every
/// ChatGPT state × stored-key combination maps to one title and one next action.
struct CoachConnectionStatus: Equatable {
    enum Kind: Equatable {
        case notConnected
        case chatGPTConnected(email: String?)
        case keyConnected(CoachConnection)
        case planUsageDisabled
        case usageLimited
        case notEligible
        case needsReconnect
    }

    enum Action: Equatable {
        case none
        /// Repeat OAuth asking for plan-usage consent again.
        case allowPlanUse
        /// Open ChatGPT usage settings.
        case manageUsage
        case reconnect
    }

    static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!

    let kind: Kind

    init(selected: CoachConnection, chatGPT: ChatGPTConnectionState, hasAnthropicKey: Bool, hasOpenAIKey: Bool) {
        switch selected {
        case .chatGPT:
            switch chatGPT {
            case .signedOut: kind = .notConnected
            case .connected(let email): kind = .chatGPTConnected(email: email)
            case .planUsageDisabled: kind = .planUsageDisabled
            case .usageLimited: kind = .usageLimited
            case .notEligible: kind = .notEligible
            case .needsReconnect: kind = .needsReconnect
            }
        case .anthropicKey:
            kind = hasAnthropicKey ? .keyConnected(.anthropicKey) : .notConnected
        case .openAIKey:
            kind = hasOpenAIKey ? .keyConnected(.openAIKey) : .notConnected
        }
    }

    var action: Action {
        switch kind {
        case .planUsageDisabled: .allowPlanUse
        case .usageLimited: .manageUsage
        case .needsReconnect: .reconnect
        case .notConnected, .chatGPTConnected, .keyConnected, .notEligible: .none
        }
    }

    /// ChatGPT states that keep chat history visible with an inline banner instead of the connect prompt.
    var isChatGPTAttention: Bool {
        switch kind {
        case .planUsageDisabled, .usageLimited, .notEligible, .needsReconnect: true
        case .notConnected, .chatGPTConnected, .keyConnected: false
        }
    }

    var isConnected: Bool {
        switch kind {
        case .chatGPTConnected, .keyConnected: true
        default: false
        }
    }

    func title(_ copy: SettingsCopy) -> String {
        switch kind {
        case .notConnected: copy.connectCoachTitle
        case .chatGPTConnected, .keyConnected: copy.coachConnected
        case .planUsageDisabled: copy.chatGPTPlanUseOffTitle
        case .usageLimited: copy.chatGPTLimitTitle
        case .notEligible: copy.chatGPTNotEligibleTitle
        case .needsReconnect: copy.reconnectChatGPTTitle
        }
    }

    func message(_ copy: SettingsCopy, model: String?) -> String {
        switch kind {
        case .notConnected: copy.connectCoachPrompt
        case .chatGPTConnected(let email): copy.usingChatGPTPlan(email: email, model: model)
        case .keyConnected: copy.modelSelected(copy.modelLabel(model ?? ""))
        case .planUsageDisabled: copy.chatGPTPlanUseOffMessage
        case .usageLimited: copy.chatGPTLimitMessage
        case .notEligible: copy.chatGPTNotEligibleMessage
        case .needsReconnect: copy.reconnectChatGPTMessage
        }
    }

    func actionTitle(_ copy: SettingsCopy) -> String? {
        switch action {
        case .none: nil
        case .allowPlanUse: copy.allowPlanUse
        case .manageUsage: copy.manageUsage
        case .reconnect: copy.reconnect
        }
    }

    var symbol: String {
        switch kind {
        case .notConnected: "sparkles"
        case .chatGPTConnected, .keyConnected: "checkmark.circle.fill"
        case .planUsageDisabled: "hand.raised.fill"
        case .usageLimited: "gauge.with.dots.needle.100percent"
        case .notEligible: "xmark.octagon.fill"
        case .needsReconnect: "arrow.triangle.2.circlepath"
        }
    }
}
