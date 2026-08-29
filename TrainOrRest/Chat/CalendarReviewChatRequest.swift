import Foundation

struct CalendarReviewChatRequest: Identifiable, Equatable {
    let id: String
    let activityUUID: UUID?
    let prompt: String
    let threadTitle: String
    let actionTypeOverride: CoachRequestActionType?
    let autoSubmit: Bool

    init(
        activityUUID: UUID,
        prompt: String = "Review cuộc chạy này giúp tôi: điểm nào ổn, điểm nào nên chỉnh, và buổi sau nên chạy thế nào?"
    ) {
        self.id = "activity-\(activityUUID.uuidString)-\(Self.stableID(prompt))"
        self.activityUUID = activityUUID
        self.prompt = prompt
        self.threadTitle = "Run review"
        self.actionTypeOverride = .readOnly
        self.autoSubmit = false
    }

    init(
        id: String? = nil,
        prompt: String,
        threadTitle: String = "Calendar schedule review",
        actionTypeOverride: CoachRequestActionType? = nil,
        autoSubmit: Bool = false
    ) {
        self.id = id ?? "prompt-\(Self.stableID(prompt))"
        self.activityUUID = nil
        self.prompt = prompt
        self.threadTitle = threadTitle
        self.actionTypeOverride = actionTypeOverride
        self.autoSubmit = autoSubmit
    }

    private static func stableID(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let characters = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(characters)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "request" : collapsed
    }
}
