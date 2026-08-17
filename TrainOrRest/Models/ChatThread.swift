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
    /// CompletedActivity.hkUUID for Calendar-created review threads. Optional so
    /// existing SwiftData stores migrate lightly and normal chats stay generic.
    var reviewActivityUUID: UUID?

    init(
        uuid: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        pinnedAt: Date? = nil,
        archivedAt: Date? = nil,
        reviewActivityUUID: UUID? = nil
    ) {
        self.uuid = uuid
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.archivedAt = archivedAt
        self.reviewActivityUUID = reviewActivityUUID
    }
}
