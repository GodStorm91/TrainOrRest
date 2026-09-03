import Foundation

struct CalendarReviewChatRequest: Identifiable, Equatable {
    let id: String
    let activityUUID: UUID?
    let displayText: String
    let prompt: String
    let threadTitle: String
    let actionTypeOverride: CoachRequestActionType?
    let autoSubmit: Bool
    let expectedResponseInteraction: CoachResponseInteraction?
    let contextSnapshotId: String?
    let contextItems: [CoachContextItem]
    let shouldFocusComposer: Bool

    init(
        activityUUID: UUID,
        prompt: String = "Review cuộc chạy này giúp tôi: điểm nào ổn, điểm nào nên chỉnh, và buổi sau nên chạy thế nào?"
    ) {
        self.id = "activity-\(activityUUID.uuidString)-\(Self.stableID(prompt))"
        self.activityUUID = activityUUID
        self.displayText = prompt
        self.prompt = prompt
        self.threadTitle = "Run review"
        self.actionTypeOverride = .readOnly
        self.autoSubmit = false
        self.expectedResponseInteraction = nil
        self.contextSnapshotId = nil
        self.contextItems = []
        self.shouldFocusComposer = true
    }

    init(
        id: String? = nil,
        displayText: String? = nil,
        prompt: String,
        threadTitle: String = "Calendar schedule review",
        actionTypeOverride: CoachRequestActionType? = nil,
        autoSubmit: Bool = false,
        expectedResponseInteraction: CoachResponseInteraction? = nil,
        contextSnapshotId: String? = nil,
        contextItems: [CoachContextItem] = [],
        shouldFocusComposer: Bool? = nil
    ) {
        self.id = id ?? "prompt-\(Self.stableID(prompt))"
        self.activityUUID = nil
        self.displayText = displayText ?? prompt
        self.prompt = prompt
        self.threadTitle = threadTitle
        self.actionTypeOverride = actionTypeOverride
        self.autoSubmit = autoSubmit
        self.expectedResponseInteraction = expectedResponseInteraction
        self.contextSnapshotId = contextSnapshotId
        self.contextItems = contextItems
        self.shouldFocusComposer = shouldFocusComposer ?? !autoSubmit
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

struct CoachContextItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case raceGoal
        case remainingPlan
        case trainingPlan
        case healthData
        case workout
        case completedRun
        case planAssessment
    }

    var id: String
    var type: Kind
    var label: String

    init(id: String? = nil, type: Kind, label: String) {
        self.id = id ?? "\(type.rawValue)-\(Self.stableID(label))"
        self.type = type
        self.label = label
    }

    private static func stableID(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}
