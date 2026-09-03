import XCTest
@testable import TrainOrRest

/// Property tests: across random goals, fitness levels, and availability
/// configurations, generated plans must always pass every validator invariant.
final class PlanPropertyTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    func testGeneratedPlansNeverViolateInvariants() {
        var rng = SeededGenerator(seed: 0xC0FFEE)
        let baseDate = PlanEngineTestSupport.date(2026, 7, 6) // Monday

        for iteration in 0..<100 {
            // Rotate the anchor across all weekdays — partial-week handling
            // depends on where in the week the plan starts.
            let today = calendar.date(byAdding: .day, value: iteration % 7, to: baseDate)!
            let distance = RaceDistance.allCases.randomElement(using: &rng)!
            let daysOut = Int.random(in: 3...150, using: &rng)
            let raceDate = calendar.date(byAdding: .day, value: daysOut, to: today)!
            let dayCount = Int.random(in: 3...7, using: &rng)
            let availableDays = Set(Weekday.allCases.shuffled(using: &rng).prefix(dayCount))
            let longRunDay = availableDays.sorted().randomElement(using: &rng)!
            let paceSecondsPerKm = Double.random(in: 240...420, using: &rng)

            let goal = GoalSpec(
                distance: distance,
                targetTimeSeconds: paceSecondsPerKm * distance.kilometers,
                raceDate: raceDate,
                availableDays: availableDays,
                longRunDay: longRunDay
            )
            let fitness = FitnessProfile(
                vdot: Double.random(in: 35...58, using: &rng),
                weeklyVolumeKm: Double.random(in: 18...75, using: &rng),
                volumeTrend: 0,
                longestRecentRunKm: Double.random(in: 8...30, using: &rng)
            )

            let plan = PlanGenerator.generate(goal: goal, fitness: fitness, today: today, calendar: calendar)
            let issues = PlanValidator.validate(plan, calendar: calendar)
            XCTAssertTrue(
                issues.isEmpty,
                "iteration \(iteration): \(issues.map(\.message)) — days \(availableDays.sorted().map(\.shortName)), long \(longRunDay.shortName), \(distance.rawValue), \(daysOut)d out, volume \(fitness.weeklyVolumeKm)"
            )

            // Explicit spot invariants beyond the validator call.
            for week in plan.weeks {
                for workout in week.workouts where workout.kind != .race {
                    XCTAssertTrue(
                        availableDays.contains(PlanGenerator.weekday(of: workout.date, calendar: calendar)),
                        "iteration \(iteration): \(workout.kind.rawValue) on unavailable day"
                    )
                }
                for workout in week.workouts where workout.kind == .long {
                    XCTAssertLessThanOrEqual(workout.distanceKm, PlanGenerator.Tuning.longRunCapKm)
                }

                // Every workout belongs to the week that actually contains it,
                // so a coach-created workout can trust the week's metadata.
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: week.startDate)!
                for workout in week.workouts {
                    XCTAssertTrue(
                        workout.date >= week.startDate && workout.date < weekEnd,
                        "iteration \(iteration): \(workout.kind.rawValue) outside week \(week.index)"
                    )
                }
            }

            // A day never holds two workouts — the invariant `create` relies on
            // when it rejects a collision.
            let days = plan.weeks.flatMap(\.workouts).map { calendar.startOfDay(for: $0.date) }
            XCTAssertEqual(Set(days).count, days.count, "iteration \(iteration): two workouts on one day")

            // A stored structure always accounts for the distance it claims.
            for workout in plan.weeks.flatMap(\.workouts) where !workout.structure.isEmpty {
                XCTAssertEqual(
                    WorkoutStructure.totalDistanceKm(workout.structure),
                    workout.distanceKm,
                    accuracy: PlanValidator.volumeEpsilonKm,
                    "iteration \(iteration): \(workout.kind.rawValue) structure does not match its distance"
                )
            }

            // Determinism per configuration.
            let again = PlanGenerator.generate(goal: goal, fitness: fitness, today: today, calendar: calendar)
            XCTAssertEqual(plan, again, "iteration \(iteration): non-deterministic output")
        }
    }

    /// Whatever the coach asks for, a workout the factory builds is always
    /// positive, self-consistent, fully paced, and describable.
    func testFactoryBuiltWorkoutsAlwaysSatisfyCreateInvariants() throws {
        var rng = SeededGenerator(seed: 0xFEEDBEEF)

        for iteration in 0..<50 {
            let paces = VDOTTable.trainingPaces(vdot: Double.random(in: 35...58, using: &rng))
            let built = [
                WorkoutFactory.canonicalEasy(distanceKm: Double.random(in: 4...12, using: &rng), paces: paces),
                WorkoutFactory.canonicalLong(distanceKm: Double.random(in: 10...30, using: &rng), paces: paces),
                WorkoutFactory.canonicalTempo(tempoKm: Double(Int.random(in: 3...8, using: &rng)), paces: paces),
                WorkoutFactory.canonicalIntervals(repCount: Int.random(in: 3...8, using: &rng), paces: paces)
            ]

            for workout in built {
                XCTAssertGreaterThan(workout.distanceKm, 0, "iteration \(iteration)")
                XCTAssertLessThanOrEqual(workout.distanceKm, WorkoutFactory.Limits.maxTotalDistanceKm)
                XCTAssertEqual(
                    WorkoutStructure.totalDistanceKm(workout.structure),
                    workout.distanceKm,
                    accuracy: 0.05,
                    "iteration \(iteration): \(workout.kind.rawValue) structure/distance mismatch"
                )
                XCTAssertFalse(workout.details.isEmpty)
                for step in workout.structure.flatMap(\.steps) {
                    XCTAssertNotNil(step.paceBand, "every canonical step resolves an app pace")
                }
                // The same recipe must also survive the untrusted-input path.
                XCTAssertNoThrow(try WorkoutFactory.build(recipe(for: workout), paces: paces))
            }
        }
    }

    /// Rebuilds a recipe from a built workout so canonical output can be pushed
    /// back through the validating `build` path.
    private func recipe(for workout: BuiltWorkout) -> WorkoutRecipe {
        WorkoutRecipe(kind: workout.kind, blocks: workout.structure.map { group in
            WorkoutRecipe.Block(repeatCount: group.repeatCount, steps: group.steps.map { step in
                WorkoutRecipe.Step(
                    role: step.role,
                    distanceKm: step.distanceKm,
                    durationSeconds: step.durationSeconds,
                    zone: zone(for: step, kind: workout.kind)
                )
            })
        })
    }

    private func zone(for step: WorkoutStep, kind: WorkoutKind) -> PaceZone {
        switch (kind, step.role) {
        case (.tempo, .work): .threshold
        case (.intervals, .work): .interval
        default: .easy
        }
    }
}
