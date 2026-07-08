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

    init(role: ChatRole, text: String, date: Date, appliedAdjustment: String? = nil) {
        self.roleRaw = role.rawValue
        self.text = text
        self.date = date
        self.appliedAdjustment = appliedAdjustment
    }

    var role: ChatRole {
        ChatRole(rawValue: roleRaw) ?? .assistant
    }
}
