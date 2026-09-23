import Foundation
import SwiftData

enum WorkoutStatus: String, Codable {
    case planned, done, skipped
}

/// One scheduled workout of the active plan.
@Model
final class PlannedWorkout {
    @Attribute(.unique) var uuid: UUID
    var date: Date
    var weekIndex: Int
    var phaseRaw: String
    var kindRaw: String
    var distanceKm: Double
    var paceFastSecondsPerKm: Double?
    var paceSlowSecondsPerKm: Double?
    var details: String
    var structure: [WorkoutStepGroup] = []
    var statusRaw: String
    /// Marks user-owned content that plan regeneration keeps.
    var manuallyOverridden: Bool
    var matchedActivityUUID: UUID?
    /// Activity links the athlete explicitly rejected for this workout.
    var dismissedActivityUUIDs: [UUID]?
    var shoeID: UUID?
    var shoeAssignmentSourceRaw: String?
    var scheduleUpdatedFromRaw: String?
    var scheduleUpdatedAt: Date?
    var scheduleLock: Bool?
    var plan: TrainingPlan?

    init(spec: PlannedWorkoutSpec, weekIndex: Int, phase: TrainingPhase) {
        self.uuid = UUID()
        self.date = spec.date
        self.weekIndex = weekIndex
        self.phaseRaw = phase.rawValue
        self.kindRaw = spec.kind.rawValue
        self.distanceKm = spec.distanceKm
        self.paceFastSecondsPerKm = spec.paceBand?.fastSecondsPerKm
        self.paceSlowSecondsPerKm = spec.paceBand?.slowSecondsPerKm
        self.details = spec.details
        self.structure = spec.structure
        self.statusRaw = WorkoutStatus.planned.rawValue
        self.manuallyOverridden = false
        self.matchedActivityUUID = nil
        self.dismissedActivityUUIDs = nil
        self.shoeID = nil
        self.shoeAssignmentSourceRaw = ShoeAssignmentSource.none.rawValue
        self.scheduleUpdatedFromRaw = nil
        self.scheduleUpdatedAt = nil
        self.scheduleLock = false
    }

    var kind: WorkoutKind? { WorkoutKind(rawValue: kindRaw) }

    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var paceBand: PaceBand? {
        guard let fast = paceFastSecondsPerKm, let slow = paceSlowSecondsPerKm else { return nil }
        return PaceBand(fastSecondsPerKm: fast, slowSecondsPerKm: slow)
    }

    var scheduleUpdatedFrom: String? {
        get { scheduleUpdatedFromRaw }
        set { scheduleUpdatedFromRaw = newValue }
    }

    var isScheduleLocked: Bool {
        get { scheduleLock ?? false }
        set { scheduleLock = newValue }
    }

    /// Expected duration from distance × mid pace; used for activity matching.
    var expectedDurationSeconds: Double? {
        guard let band = paceBand else { return nil }
        let midPace = (band.fastSecondsPerKm + band.slowSecondsPerKm) / 2
        return distanceKm * midPace
    }

    var matcherRef: WorkoutMatcher.PlannedRef {
        WorkoutMatcher.PlannedRef(
            id: uuid,
            date: date,
            expectedDurationSeconds: expectedDurationSeconds,
            dismissedActivityIDs: Set(dismissedActivityUUIDs ?? [])
        )
    }

    func isLinkDismissed(_ activityID: UUID) -> Bool {
        dismissedActivityUUIDs?.contains(activityID) ?? false
    }

    func dismissLink(_ activityID: UUID) {
        guard !isLinkDismissed(activityID) else { return }
        var dismissed = dismissedActivityUUIDs ?? []
        dismissed.append(activityID)
        dismissedActivityUUIDs = dismissed
    }

    func clearLinkDismissal(_ activityID: UUID) {
        let remaining = (dismissedActivityUUIDs ?? []).filter { $0 != activityID }
        dismissedActivityUUIDs = remaining.isEmpty ? nil : remaining
    }

    /// When several planned rows share a calendar day, keep the one that
    /// still has a shoe assignment, then any manual override, then a stable uuid.
    static func preferredAmongDuplicates(_ group: [PlannedWorkout]) -> PlannedWorkout? {
        group.max { a, b in
            let aScore = (a.shoeID != nil ? 2 : 0) + (a.manuallyOverridden ? 1 : 0)
            let bScore = (b.shoeID != nil ? 2 : 0) + (b.manuallyOverridden ? 1 : 0)
            if aScore != bScore { return aScore < bScore }
            return a.uuid.uuidString > b.uuid.uuidString
        }
    }

}
