import Foundation
import SwiftData

/// Journal entry for an applied coach replacement. The row stores the exact
/// fields needed to invert the edit while refusing to clobber later changes.
@Model
final class PlanEdit {
    @Attribute(.unique) var id: UUID
    var appliedAt: Date
    var workoutUUID: UUID
    var workoutDate: Date
    var weekIndex: Int

    var kindRaw: String
    var distanceKm: Double
    var paceFastSecondsPerKm: Double?
    var paceSlowSecondsPerKm: Double?
    var details: String
    var structure: [WorkoutStepGroup] = []
    var statusRaw: String
    var manuallyOverridden: Bool
    var matchedActivityUUID: UUID?
    var weekTargetVolumeKmBefore: Double

    var afterKindRaw: String
    var afterDistanceKm: Double
    var afterPaceFastSecondsPerKm: Double?
    var afterPaceSlowSecondsPerKm: Double?
    var afterDetails: String
    var afterStructure: [WorkoutStepGroup] = []
    var afterStatusRaw: String
    var afterManuallyOverridden: Bool
    var afterMatchedActivityUUID: UUID?
    var weekTargetVolumeKmAfter: Double

    var revertedAt: Date?
    var source: String

    init(
        appliedAt: Date,
        workout: PlannedWorkout,
        weekTargetVolumeKmBefore: Double,
        afterKindRaw: String,
        afterDistanceKm: Double,
        afterPaceFastSecondsPerKm: Double?,
        afterPaceSlowSecondsPerKm: Double?,
        afterDetails: String,
        afterStructure: [WorkoutStepGroup],
        afterStatusRaw: String,
        afterManuallyOverridden: Bool,
        afterMatchedActivityUUID: UUID?,
        weekTargetVolumeKmAfter: Double,
        source: String = "coach"
    ) {
        self.id = UUID()
        self.appliedAt = appliedAt
        self.workoutUUID = workout.uuid
        self.workoutDate = workout.date
        self.weekIndex = workout.weekIndex
        self.kindRaw = workout.kindRaw
        self.distanceKm = workout.distanceKm
        self.paceFastSecondsPerKm = workout.paceFastSecondsPerKm
        self.paceSlowSecondsPerKm = workout.paceSlowSecondsPerKm
        self.details = workout.details
        self.structure = workout.structure
        self.statusRaw = workout.statusRaw
        self.manuallyOverridden = workout.manuallyOverridden
        self.matchedActivityUUID = workout.matchedActivityUUID
        self.weekTargetVolumeKmBefore = weekTargetVolumeKmBefore
        self.afterKindRaw = afterKindRaw
        self.afterDistanceKm = afterDistanceKm
        self.afterPaceFastSecondsPerKm = afterPaceFastSecondsPerKm
        self.afterPaceSlowSecondsPerKm = afterPaceSlowSecondsPerKm
        self.afterDetails = afterDetails
        self.afterStructure = afterStructure
        self.afterStatusRaw = afterStatusRaw
        self.afterManuallyOverridden = afterManuallyOverridden
        self.afterMatchedActivityUUID = afterMatchedActivityUUID
        self.weekTargetVolumeKmAfter = weekTargetVolumeKmAfter
        self.revertedAt = nil
        self.source = source
    }

    var beforeKind: WorkoutKind? { WorkoutKind(rawValue: kindRaw) }
    var afterKind: WorkoutKind? { WorkoutKind(rawValue: afterKindRaw) }
}

@MainActor
enum PlanEditStore {
    static let revertWindowDays = 7
    static let changedAfterEditMessage = "This session changed after the coach edit; revert manually."
    private static let distanceTolerance = 0.001

    static func revert(
        _ editId: UUID,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws {
        let descriptor = FetchDescriptor<PlanEdit>(
            predicate: #Predicate { $0.id == editId }
        )
        guard let edit = try context.fetch(descriptor).first else {
            throw CoachTools.ValidationError("Coach edit was not found.")
        }
        try revert(edit, in: context, today: today, calendar: calendar)
    }

    static func revert(
        _ edit: PlanEdit,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws {
        guard edit.revertedAt == nil else {
            throw CoachTools.ValidationError("That coach edit was already reverted.")
        }
        let cutoff = calendar.date(byAdding: .day, value: -revertWindowDays, to: today) ?? today
        guard edit.appliedAt >= cutoff else {
            throw CoachTools.ValidationError("Coach edits can only be reverted for 7 days.")
        }
        guard let plan = try PlanStore.activePlan(in: context),
              plan.weekTargetVolumesKm.indices.contains(edit.weekIndex) else {
            throw CoachTools.ValidationError(changedAfterEditMessage)
        }
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        guard let workout = workouts.first(where: { $0.uuid == edit.workoutUUID }),
              calendar.isDate(workout.date, inSameDayAs: edit.workoutDate),
              workout.weekIndex == edit.weekIndex,
              workout.kindRaw == edit.afterKindRaw,
              isClose(workout.distanceKm, edit.afterDistanceKm),
              workout.paceFastSecondsPerKm == edit.afterPaceFastSecondsPerKm,
              workout.paceSlowSecondsPerKm == edit.afterPaceSlowSecondsPerKm,
              workout.details == edit.afterDetails,
              workout.structure == edit.afterStructure,
              workout.statusRaw == edit.afterStatusRaw,
              workout.manuallyOverridden == edit.afterManuallyOverridden,
              workout.matchedActivityUUID == edit.afterMatchedActivityUUID,
              isClose(plan.weekTargetVolumesKm[edit.weekIndex], edit.weekTargetVolumeKmAfter) else {
            throw CoachTools.ValidationError(changedAfterEditMessage)
        }

        workout.kindRaw = edit.kindRaw
        workout.distanceKm = edit.distanceKm
        workout.paceFastSecondsPerKm = edit.paceFastSecondsPerKm
        workout.paceSlowSecondsPerKm = edit.paceSlowSecondsPerKm
        workout.details = edit.details
        workout.structure = edit.structure
        workout.statusRaw = edit.statusRaw
        workout.manuallyOverridden = edit.manuallyOverridden
        workout.matchedActivityUUID = edit.matchedActivityUUID

        var targets = plan.weekTargetVolumesKm
        targets[edit.weekIndex] = edit.weekTargetVolumeKmBefore
        plan.weekTargetVolumesKm = targets
        edit.revertedAt = today

        try context.save()
        NotificationCenter.default.post(name: .planDidChange, object: nil)
    }

    private static func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= distanceTolerance
    }
}
