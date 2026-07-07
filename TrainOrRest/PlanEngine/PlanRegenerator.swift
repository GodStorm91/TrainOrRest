import Foundation

/// Daily plan regeneration under the stability contract: the future schedule
/// is always derived race-backward from goal + current fitness (never from
/// yesterday's plan), so unchanged inputs reproduce a byte-identical plan.
/// Readiness only modulates the current week — today's hard session is
/// swapped with a later easy day when spacing allows, else downgraded/dropped.
enum PlanRegenerator {
    static func regenerate(
        goal: GoalSpec,
        fitness: FitnessProfile,
        verdict: ReadinessVerdict,
        today: Date,
        calendar: Calendar
    ) -> TrainingPlanSpec {
        var plan = PlanGenerator.generate(goal: goal, fitness: fitness, today: today, calendar: calendar)
        guard !plan.weeks.isEmpty, verdict == .goEasy || verdict == .rest else { return plan }

        modulateToday(&plan, verdict: verdict, fitness: fitness, today: today, calendar: calendar)
        assert(
            PlanValidator.validate(plan, calendar: calendar).isEmpty,
            "Modulated plan violates validator invariants"
        )
        return plan
    }

    private static func modulateToday(
        _ plan: inout TrainingPlanSpec,
        verdict: ReadinessVerdict,
        fitness: FitnessProfile,
        today: Date,
        calendar: Calendar
    ) {
        let dayStart = calendar.startOfDay(for: today)
        var week = plan.weeks[0]
        guard let todayIndex = week.workouts.firstIndex(where: { $0.date == dayStart }) else { return }
        let todayWorkout = week.workouts[todayIndex]
        // Race day is never modulated — that decision belongs to the runner.
        guard todayWorkout.kind != .race else { return }

        // Try to move a displaced hard session onto a later easy day of the
        // same week, keeping ≥1 recovery day to every other hard session
        // (including next week's and the race).
        if todayWorkout.kind.isQuality {
            let otherHardDates = plan.weeks
                .flatMap(\.workouts)
                .filter { $0.kind.isQuality && $0.date != dayStart }
                .map(\.date)
            let raceDay = calendar.startOfDay(for: plan.goal.raceDate)

            let target = week.workouts.enumerated().first { index, candidate in
                candidate.kind == .easy && candidate.date > dayStart
                    && PlanGenerator.daysBetween(candidate.date, raceDay, calendar: calendar) >= 2
                    && otherHardDates.allSatisfy {
                        abs(PlanGenerator.daysBetween($0, candidate.date, calendar: calendar)) >= 2
                    }
            }

            if let (targetIndex, targetWorkout) = target {
                // Swap content; dates stay put.
                week.workouts[targetIndex] = reslotted(todayWorkout, to: targetWorkout.date)
                week.workouts[todayIndex] = reslotted(targetWorkout, to: dayStart)
            }
        }

        // After any swap, today holds the lighter session — apply the verdict.
        let paces = VDOTTable.trainingPaces(vdot: fitness.vdot)
        switch verdict {
        case .rest:
            week.workouts.remove(
                at: week.workouts.firstIndex { $0.date == dayStart }!
            )
        case .goEasy:
            let index = week.workouts.firstIndex { $0.date == dayStart }!
            let current = week.workouts[index]
            if current.kind != .easy {
                // No swap target was found — downgrade in place. Long runs
                // shrink; shorter quality keeps its distance at easy effort.
                let distance = current.kind == .long
                    ? PlanGenerator.rounded(current.distanceKm * 0.6)
                    : current.distanceKm
                week.workouts[index] = PlannedWorkoutSpec(
                    date: dayStart,
                    kind: .easy,
                    distanceKm: distance,
                    paceBand: paces.easy,
                    details: "Easy run at E pace"
                )
            }
        default:
            break
        }

        // targetVolumeKm stays the planned trajectory value: later weeks'
        // ramp is validated against it, and modulation only changes actuals.
        plan.weeks[0] = week
    }

    private static func reslotted(_ workout: PlannedWorkoutSpec, to date: Date) -> PlannedWorkoutSpec {
        var moved = workout
        moved.date = date
        return moved
    }
}
