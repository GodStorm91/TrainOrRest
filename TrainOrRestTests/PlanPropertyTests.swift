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
            }

            // Determinism per configuration.
            let again = PlanGenerator.generate(goal: goal, fitness: fitness, today: today, calendar: calendar)
            XCTAssertEqual(plan, again, "iteration \(iteration): non-deterministic output")
        }
    }
}
