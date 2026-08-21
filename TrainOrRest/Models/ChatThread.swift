import Foundation
import SwiftData

@Model
final class ChatThread {
    enum Mode: String, Codable {
        case general
        case workoutEdit
        case workoutReview
        case planReview
    }

    var uuid: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var pinnedAt: Date?
    var archivedAt: Date?
    /// CompletedActivity.hkUUID for Calendar-created review threads. Optional so
    /// existing SwiftData stores migrate lightly and normal chats stay generic.
    var reviewActivityUUID: UUID?
    var modeRaw: String?
    var linkedWorkoutUUID: UUID?
    var linkedPlanUUID: UUID?
    var contextualSnapshotJSON: String?

    init(
        uuid: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        pinnedAt: Date? = nil,
        archivedAt: Date? = nil,
        reviewActivityUUID: UUID? = nil,
        mode: Mode = .general,
        linkedWorkoutUUID: UUID? = nil,
        linkedPlanUUID: UUID? = nil,
        contextualSnapshotJSON: String? = nil
    ) {
        self.uuid = uuid
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.archivedAt = archivedAt
        self.reviewActivityUUID = reviewActivityUUID
        self.modeRaw = mode.rawValue
        self.linkedWorkoutUUID = linkedWorkoutUUID
        self.linkedPlanUUID = linkedPlanUUID
        self.contextualSnapshotJSON = contextualSnapshotJSON
    }

    var mode: Mode {
        get { Mode(rawValue: modeRaw ?? "") ?? .general }
        set { modeRaw = newValue.rawValue }
    }
}

struct WorkoutCoachContext: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case planned
        case completed
        case locked
        case unavailable
    }

    var id: UUID
    var workoutId: UUID?
    var completedActivityId: UUID?
    var trainingPlanId: UUID?
    var calendarDate: Date
    var workoutStatus: Status
    var workoutType: String
    var workoutTitle: String
    var plannedDistanceKm: Double?
    var actualDistanceMeters: Double?
    var plannedDurationSeconds: Double?
    var actualDurationSeconds: Double?
    var plannedPaceFastSecondsPerKm: Double?
    var plannedPaceSlowSecondsPerKm: Double?
    var plannedIntensity: String?
    var workoutStructureSummary: String?
    var isKeyWorkout: Bool
    var phaseId: String?
    var phaseName: String?
    var planWeek: Int?
    var nearbyWorkoutIds: [UUID]
    var sourceScreen: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        workoutId: UUID?,
        completedActivityId: UUID? = nil,
        trainingPlanId: UUID?,
        calendarDate: Date,
        workoutStatus: Status,
        workoutType: String,
        workoutTitle: String,
        plannedDistanceKm: Double?,
        actualDistanceMeters: Double? = nil,
        plannedDurationSeconds: Double?,
        actualDurationSeconds: Double? = nil,
        plannedPaceFastSecondsPerKm: Double?,
        plannedPaceSlowSecondsPerKm: Double?,
        plannedIntensity: String?,
        workoutStructureSummary: String?,
        isKeyWorkout: Bool,
        phaseId: String?,
        phaseName: String?,
        planWeek: Int?,
        nearbyWorkoutIds: [UUID],
        sourceScreen: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workoutId = workoutId
        self.completedActivityId = completedActivityId
        self.trainingPlanId = trainingPlanId
        self.calendarDate = calendarDate
        self.workoutStatus = workoutStatus
        self.workoutType = workoutType
        self.workoutTitle = workoutTitle
        self.plannedDistanceKm = plannedDistanceKm
        self.actualDistanceMeters = actualDistanceMeters
        self.plannedDurationSeconds = plannedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.plannedPaceFastSecondsPerKm = plannedPaceFastSecondsPerKm
        self.plannedPaceSlowSecondsPerKm = plannedPaceSlowSecondsPerKm
        self.plannedIntensity = plannedIntensity
        self.workoutStructureSummary = workoutStructureSummary
        self.isKeyWorkout = isKeyWorkout
        self.phaseId = phaseId
        self.phaseName = phaseName
        self.planWeek = planWeek
        self.nearbyWorkoutIds = nearbyWorkoutIds
        self.sourceScreen = sourceScreen
        self.createdAt = createdAt
    }

    static func encode(_ snapshot: WorkoutCoachContext) -> String? {
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> WorkoutCoachContext? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkoutCoachContext.self, from: data)
    }
}
