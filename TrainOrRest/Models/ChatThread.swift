import Foundation
import SwiftData

@Model
final class ChatThread {
    var uuid: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var pinnedAt: Date?
    var archivedAt: Date?

    init(
        uuid: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        pinnedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.uuid = uuid
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.archivedAt = archivedAt
    }
}
