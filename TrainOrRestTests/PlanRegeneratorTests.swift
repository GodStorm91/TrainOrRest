import XCTest
@testable import TrainOrRest

final class PlanRegeneratorTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    // Availability includes Monday/Wednesday/Friday so mid-week test days
    // carry workouts; long run Sunday → quality lands on Wednesday.
    private var goal: GoalSpec {
        GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 4, 19), // Sunday
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday
        )
    }

    private var fitness: FitnessProfile {
        FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0, longestRecentRunKm: 16)
    }

    private func regenerate(verdict: ReadinessVerdict, today: Date) -> TrainingPlanSpec {
        PlanRegenerator.regenerate(
            goal: goal, fitness: fitness, verdict: verdict, today: today, calendar: calendar
        )
    }

    private func regenerate(goal: GoalSpec, verdict: ReadinessVerdict, today: Date) -> TrainingPlanSpec {
        PlanRegenerator.regenerate(
            goal: goal, fitness: fitness, verdict: verdict, today: today, calendar: calendar
        )
    }

    private let qualityDay = PlanEngineTestSupport.date(2026, 1, 7) // Wednesday

    func testTrainVerdictMatchesPlainGeneration() {
        let plain = PlanGenerator.generate(goal: goal, fitness: fitness, today: qualityDay, calendar: calendar)
        XCTAssertEqual(regenerate(verdict: .train, today: qualityDay), plain)
        XCTAssertEqual(regenerate(verdict: .insufficientData, today: qualityDay), plain)
    }

    func testRegenerationIsDeterministic() {
        XCTAssertEqual(
            regenerate(verdict: .goEasy, today: qualityDay),
            regenerate(verdict: .goEasy, today: qualityDay)
        )
    }

    func testGoEasyOnQualityDaySwapsWithLaterEasyDay() {
        let plan = regenerate(verdict: .goEasy, today: qualityDay)
        let week = plan.weeks[0]
        let dayStart = calendar.startOfDay(for: qualityDay)

        let todayWorkout = week.workouts.first { $0.date == dayStart }
        XCTAssertEqual(todayWorkout?.kind, .easy)
        // The displaced tempo lands on Friday (the later easy day).
        let friday = calendar.date(byAdding: .day, value: 2, to: dayStart)!
        let fridayWorkout = week.workouts.first { $0.date == friday }
        XCTAssertEqual(fridayWorkout?.kind, .tempo)
        XCTAssertTrue(PlanValidator.validate(plan, calendar: calendar).isEmpty)
    }

    func testGoEasyDowngradeWithoutSwapKeepsStructure() {
        let noLaterEasyGoal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 4, 19),
            availableDays: [.monday, .wednesday, .sunday],
            longRunDay: .sunday
        )
        let plan = regenerate(goal: noLaterEasyGoal, verdict: .goEasy, today: qualityDay)
        let todayWorkout = plan.weeks[0].workouts.first {
            $0.date == calendar.startOfDay(for: qualityDay)
        }

        XCTAssertEqual(todayWorkout?.kind, .easy)
        XCTAssertEqual(todayWorkout?.details, "Easy run at E pace")
        XCTAssertEqual(todayWorkout?.structure.isEmpty, false)
        XCTAssertEqual(todayWorkout?.structure.first?.steps.map(\.role), [.work])
        XCTAssertTrue(PlanValidator.validate(plan, calendar: calendar).isEmpty)
    }

    func testRestOnQualityDayRemovesTodayAndKeepsReslottedQuality() {
        let plan = regenerate(verdict: .rest, today: qualityDay)
        let week = plan.weeks[0]
        let dayStart = calendar.startOfDay(for: qualityDay)

        XCTAssertNil(week.workouts.first { $0.date == dayStart })
        let friday = calendar.date(byAdding: .day, value: 2, to: dayStart)!
        XCTAssertEqual(week.workouts.first { $0.date == friday }?.kind, .tempo)
        XCTAssertTrue(PlanValidator.validate(plan, calendar: calendar).isEmpty)
    }

    func testRestOnEasyDayJustRemovesIt() {
        let easyDay = PlanEngineTestSupport.date(2026, 1, 5) // Monday
        let plan = regenerate(verdict: .rest, today: easyDay)
        XCTAssertNil(plan.weeks[0].workouts.first { $0.date == calendar.startOfDay(for: easyDay) })
        XCTAssertTrue(PlanValidator.validate(plan, calendar: calendar).isEmpty)
    }

    func testModulationTouchesOnlyCurrentWeek() {
        let trainPlan = regenerate(verdict: .train, today: qualityDay)
        let restPlan = regenerate(verdict: .rest, today: qualityDay)
        XCTAssertEqual(
            Array(trainPlan.weeks.dropFirst()),
            Array(restPlan.weeks.dropFirst()),
            "Readiness must only perturb the current week"
        )
    }

    func testRaceDayIsNeverModulated() {
        let raceDay = PlanEngineTestSupport.date(2026, 4, 19)
        let plan = regenerate(verdict: .rest, today: raceDay)
        let race = plan.weeks.flatMap(\.workouts).first { $0.kind == .race }
        XCTAssertNotNil(race, "Race must survive a rest verdict")
    }

    func testDailyRegenerationNeverOscillates() {
        // Simulate four weeks of following the plan: each day's workout is
        // completed at easy effort and feeds the next day's fitness estimate.
        var completed = PlanEngineTestSupport.history(
            weeks: 8, runsPerWeek: 4, distanceKm: 10, paceSecondsPerKm: 330,
            endingAt: PlanEngineTestSupport.date(2026, 1, 5)
        )
        for dayOffset in 0..<28 {
            let today = calendar.date(
                byAdding: .day, value: dayOffset, to: PlanEngineTestSupport.date(2026, 1, 5)
            )!
            let fitness = FitnessEstimator.estimate(samples: completed, today: today, calendar: calendar)
                ?? self.fitness
            let plan = PlanRegenerator.regenerate(
                goal: goal, fitness: fitness, verdict: .train, today: today, calendar: calendar
            )
            let again = PlanRegenerator.regenerate(
                goal: goal, fitness: fitness, verdict: .train, today: today, calendar: calendar
            )
            XCTAssertEqual(plan, again, "day \(dayOffset): same inputs must reproduce the same plan")
            XCTAssertTrue(
                PlanValidator.validate(plan, calendar: calendar).isEmpty,
                "day \(dayOffset): regenerated plan must validate"
            )

            if let todayWorkout = plan.weeks.first?.workouts.first(where: {
                $0.date == calendar.startOfDay(for: today) && $0.kind != .race
            }) {
                completed.append(RunSample(
                    date: today,
                    distanceKm: todayWorkout.distanceKm,
                    durationSeconds: todayWorkout.distanceKm * 330
                ))
            }
        }
    }
}
