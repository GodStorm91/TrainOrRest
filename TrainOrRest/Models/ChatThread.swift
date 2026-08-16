import Foundation
import SwiftData

@Model
final class ChatThread {
    var uuid: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(
        uuid: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.uuid = uuid
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
