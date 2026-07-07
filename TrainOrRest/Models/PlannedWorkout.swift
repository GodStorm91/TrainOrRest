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
    var statusRaw: String
    /// Set by user actions; auto-matching never overwrites a manual decision.
    var manuallyOverridden: Bool
    var matchedActivityUUID: UUID?
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
        self.statusRaw = WorkoutStatus.planned.rawValue
        self.manuallyOverridden = false
        self.matchedActivityUUID = nil
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

    /// Expected duration from distance × mid pace; used for activity matching.
    var expectedDurationSeconds: Double? {
        guard let band = paceBand else { return nil }
        let midPace = (band.fastSecondsPerKm + band.slowSecondsPerKm) / 2
        return distanceKm * midPace
    }
}
