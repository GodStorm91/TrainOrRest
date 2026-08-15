import Foundation
import SwiftData

enum ChatRole: String, Codable {
    case user, assistant
}

@Model
final class ChatMessage {
    var roleRaw: String
    var text: String
    var date: Date
    var appliedAdjustment: String?
    var groundingFootnote: String?
    var groundingSummary: String?

    init(
        role: ChatRole,
        text: String,
        date: Date,
        appliedAdjustment: String? = nil,
        groundingFootnote: String? = nil,
        groundingSummary: String? = nil
    ) {
        self.roleRaw = role.rawValue
        self.text = text
        self.date = date
        self.appliedAdjustment = appliedAdjustment
        self.groundingFootnote = groundingFootnote
        self.groundingSummary = groundingSummary
    }

    var role: ChatRole {
        ChatRole(rawValue: roleRaw) ?? .assistant
    }
}
