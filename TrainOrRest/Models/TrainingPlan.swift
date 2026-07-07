import Foundation
import SwiftData

/// A generated plan snapshot. Workouts cascade-delete with the plan; week
/// metadata is stored as parallel arrays indexed by week for calendar headers.
@Model
final class TrainingPlan {
    var generatedAt: Date
    var anchorDate: Date
    var weekPhasesRaw: [String]
    var weekTargetVolumesKm: [Double]
    var weekIsDown: [Bool]
    @Relationship(deleteRule: .cascade, inverse: \PlannedWorkout.plan)
    var workouts: [PlannedWorkout] = []

    init(spec: TrainingPlanSpec, generatedAt: Date) {
        self.generatedAt = generatedAt
        self.anchorDate = spec.anchorDate
        self.weekPhasesRaw = spec.weeks.map(\.phase.rawValue)
        self.weekTargetVolumesKm = spec.weeks.map(\.targetVolumeKm)
        self.weekIsDown = spec.weeks.map(\.isDownWeek)
    }

    func phase(forWeek index: Int) -> TrainingPhase? {
        guard weekPhasesRaw.indices.contains(index) else { return nil }
        return TrainingPhase(rawValue: weekPhasesRaw[index])
    }
}
