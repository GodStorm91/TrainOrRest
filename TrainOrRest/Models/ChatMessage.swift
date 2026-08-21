import Foundation
import SwiftData

enum ChatRole: String, Codable {
    case user, assistant
}

enum AssistantTurnStatus: String, Codable {
    case queued, streaming, completed, failed, retrying, dismissed, reconciling, cancelled
}

enum CoachErrorCategory: String, Codable {
    case retryableResponse
    case offline
    case missingAttachment
    case authentication
    case mutationUnknown
    case nonRetryable
}

enum CoachRequestActionType: String, Codable {
    case readOnly
    case planMutation
}

@Model
final class ChatMessage {
    // Optional for lightweight migration from existing stores. Older chat rows
    // receive a stable turn ID lazily instead of forcing a launch-time schema
    // migration over historical conversation data.
    var uuid: UUID?
    var roleRaw: String
    var text: String
    var date: Date
    var appliedAdjustment: String?
    var groundingFootnote: String?
    var groundingSummary: String?
    var threadID: UUID?
    var parentUserTurnID: UUID?
    var requestSnapshotID: UUID?
    var statusRaw: String?
    var errorCategoryRaw: String?
    var errorMessage: String?
    var attemptCountStorage: Int?
    var activeAttemptID: UUID?
    var operationID: UUID?
    var isIncompleteStorage: Bool?
    var announcedFailureStorage: Bool?

    init(
        uuid: UUID = UUID(),
        role: ChatRole,
        text: String,
        date: Date,
        appliedAdjustment: String? = nil,
        groundingFootnote: String? = nil,
        groundingSummary: String? = nil,
        threadID: UUID? = nil,
        parentUserTurnID: UUID? = nil,
        requestSnapshotID: UUID? = nil,
        status: AssistantTurnStatus? = nil,
        errorCategory: CoachErrorCategory? = nil,
        errorMessage: String? = nil,
        attemptCount: Int = 0,
        activeAttemptID: UUID? = nil,
        operationID: UUID? = nil,
        isIncomplete: Bool = false,
        announcedFailure: Bool = false
    ) {
        self.uuid = uuid
        self.roleRaw = role.rawValue
        self.text = text
        self.date = date
        self.appliedAdjustment = appliedAdjustment
        self.groundingFootnote = groundingFootnote
        self.groundingSummary = groundingSummary
        self.threadID = threadID
        self.parentUserTurnID = parentUserTurnID
        self.requestSnapshotID = requestSnapshotID
        self.statusRaw = status?.rawValue
        self.errorCategoryRaw = errorCategory?.rawValue
        self.errorMessage = errorMessage
        self.attemptCountStorage = attemptCount
        self.activeAttemptID = activeAttemptID
        self.operationID = operationID
        self.isIncompleteStorage = isIncomplete
        self.announcedFailureStorage = announcedFailure
    }

    var role: ChatRole {
        ChatRole(rawValue: roleRaw) ?? .assistant
    }

    var turnID: UUID {
        get {
            if let uuid { return uuid }
            let generated = UUID()
            uuid = generated
            return generated
        }
        set {
            uuid = newValue
        }
    }

    var assistantStatus: AssistantTurnStatus {
        get { AssistantTurnStatus(rawValue: statusRaw ?? "") ?? (role == .assistant ? .completed : .completed) }
        set { statusRaw = newValue.rawValue }
    }

    var errorCategory: CoachErrorCategory? {
        get { errorCategoryRaw.flatMap(CoachErrorCategory.init(rawValue:)) }
        set { errorCategoryRaw = newValue?.rawValue }
    }

    var attemptCount: Int {
        get { attemptCountStorage ?? 0 }
        set { attemptCountStorage = newValue }
    }

    var isIncomplete: Bool {
        get { isIncompleteStorage ?? false }
        set { isIncompleteStorage = newValue }
    }

    var announcedFailure: Bool {
        get { announcedFailureStorage ?? false }
        set { announcedFailureStorage = newValue }
    }
}

@Model
final class CoachRequestSnapshot {
    @Attribute(.unique) var id: UUID
    var userTurnID: UUID
    var messageText: String
    var attachmentReferencesJSON: String
    var selectedEvidenceSourcesJSON: String
    var contextBoundaryMessageID: UUID
    var locale: String
    var unitPreferences: String
    var createdAt: Date
    var actionTypeRaw: String
    var operationID: UUID
    var groundingFootnote: String?
    var groundingSummary: String?
    var threadID: UUID?

    init(
        id: UUID = UUID(),
        userTurnID: UUID,
        messageText: String,
        attachmentReferences: [CoachAttachmentReference],
        selectedEvidenceSources: EvidenceSelection,
        contextBoundaryMessageID: UUID,
        locale: String,
        unitPreferences: String = "metric",
        createdAt: Date,
        actionType: CoachRequestActionType,
        operationID: UUID = UUID(),
        groundingSnapshot: GroundingSnapshot?,
        threadID: UUID?
    ) {
        self.id = id
        self.userTurnID = userTurnID
        self.messageText = messageText
        self.attachmentReferencesJSON = Self.encode(attachmentReferences)
        self.selectedEvidenceSourcesJSON = Self.encode(selectedEvidenceSources.snapshotPayload)
        self.contextBoundaryMessageID = contextBoundaryMessageID
        self.locale = locale
        self.unitPreferences = unitPreferences
        self.createdAt = createdAt
        self.actionTypeRaw = actionType.rawValue
        self.operationID = operationID
        self.groundingFootnote = groundingSnapshot?.footnoteLine
        self.groundingSummary = groundingSnapshot?.summary
        self.threadID = threadID
    }

    var actionType: CoachRequestActionType {
        CoachRequestActionType(rawValue: actionTypeRaw) ?? .readOnly
    }

    var attachmentReferences: [CoachAttachmentReference] {
        Self.decode([CoachAttachmentReference].self, from: attachmentReferencesJSON) ?? []
    }

    var selectedEvidenceSources: EvidenceSelection {
        (Self.decode(EvidenceSelection.Payload.self, from: selectedEvidenceSourcesJSON) ?? .default).selection
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    private static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct CoachAttachmentReference: Codable, Equatable {
    enum Kind: String, Codable {
        case health, plannedWorkout, completedActivity, image
    }

    var kind: Kind
    var uuid: UUID?
    var filename: String?
    var mediaType: String?
    var imageData: Data?
}

extension EvidenceSelection {
    struct Payload: Codable, Equatable {
        var readinessSnapshot: Bool
        var weekPlan: Bool
        var workoutKind: String?
        var workoutUUID: UUID?
        var hasPhoto: Bool

        static let `default` = Payload(
            readinessSnapshot: true,
            weekPlan: true,
            workoutKind: nil,
            workoutUUID: nil,
            hasPhoto: false
        )

        var selection: EvidenceSelection {
            let workout: WorkoutContextSelection?
            switch workoutKind {
            case "planned":
                workout = workoutUUID.map(WorkoutContextSelection.planned)
            case "completed":
                workout = workoutUUID.map(WorkoutContextSelection.completed)
            default:
                workout = nil
            }
            return EvidenceSelection(
                readinessSnapshot: readinessSnapshot,
                weekPlan: weekPlan,
                workout: workout,
                hasPhoto: hasPhoto
            )
        }
    }

    var snapshotPayload: Payload {
        let workoutKind: String?
        let workoutUUID: UUID?
        switch workout {
        case .planned(let uuid):
            workoutKind = "planned"
            workoutUUID = uuid
        case .completed(let uuid):
            workoutKind = "completed"
            workoutUUID = uuid
        case nil:
            workoutKind = nil
            workoutUUID = nil
        }
        return Payload(
            readinessSnapshot: readinessSnapshot,
            weekPlan: weekPlan,
            workoutKind: workoutKind,
            workoutUUID: workoutUUID,
            hasPhoto: hasPhoto
        )
    }
}
