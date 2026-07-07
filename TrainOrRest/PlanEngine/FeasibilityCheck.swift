import Foundation

/// Compares the goal's implied VDOT with current fitness plus a realistic
/// training gain over the time remaining. Unrealistic goals still generate a
/// plan — the verdict is a warning, not a gate.
enum FeasibilityCheck {
    /// Trainable VDOT gain per week of preparation…
    static let vdotGainPerWeek = 0.15
    /// …capped over any single training block.
    static let maxProjectedGain = 5.0
    /// Verdict is "stretch" up to this margin above the projection.
    static let stretchMarginVDOT = 3.0

    struct Assessment: Equatable {
        var verdict: FeasibilityVerdict
        var goalVDOT: Double
        var currentVDOT: Double
        var projectedVDOT: Double
    }

    static func assess(
        goal: GoalSpec,
        fitness: FitnessProfile,
        today: Date,
        calendar: Calendar
    ) -> Assessment {
        let goalVDOT = VDOTTable.vdot(
            distanceMeters: goal.distance.meters,
            timeSeconds: goal.targetTimeSeconds
        )
        let days = max(0, PlanGenerator.daysBetween(
            calendar.startOfDay(for: today),
            calendar.startOfDay(for: goal.raceDate),
            calendar: calendar
        ))
        let weeks = Double(days) / 7
        let projected = fitness.vdot + min(weeks * vdotGainPerWeek, maxProjectedGain)

        let verdict: FeasibilityVerdict = if goalVDOT <= projected {
            .ok
        } else if goalVDOT <= projected + stretchMarginVDOT {
            .stretch
        } else {
            .unrealistic
        }
        return Assessment(
            verdict: verdict,
            goalVDOT: goalVDOT,
            currentVDOT: fitness.vdot,
            projectedVDOT: projected
        )
    }
}
