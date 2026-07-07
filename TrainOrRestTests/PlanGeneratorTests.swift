import XCTest
@testable import TrainOrRest

final class PlanGeneratorTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    /// Fixture: half marathon in 1:45, 15 weeks out, 4 run days.
    private var fixtureGoal: GoalSpec {
        GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 4, 19), // Sunday
            availableDays: [.tuesday, .thursday, .saturday, .sunday],
            longRunDay: .sunday
        )
    }

    private var fixtureFitness: FitnessProfile {
        FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0.05, longestRecentRunKm: 16)
    }

    private var fixtureToday: Date { PlanEngineTestSupport.date(2026, 1, 5) } // Monday

    private func fixturePlan() -> TrainingPlanSpec {
        PlanGenerator.generate(
            goal: fixtureGoal, fitness: fixtureFitness, today: fixtureToday, calendar: calendar
        )
    }

    func testDeterminismIdenticalInputsIdenticalPlan() {
        XCTAssertEqual(fixturePlan(), fixturePlan())
    }

    func testFixturePlanShape() {
        let plan = fixturePlan()
        XCTAssertEqual(plan.weeks.count, 15)

        // Phase split: 4 base, 6 build, 3 peak, 2 taper (HM).
        let phaseCounts = Dictionary(grouping: plan.weeks, by: \.phase).mapValues(\.count)
        XCTAssertEqual(phaseCounts[.base], 4)
        XCTAssertEqual(phaseCounts[.build], 6)
        XCTAssertEqual(phaseCounts[.peak], 3)
        XCTAssertEqual(phaseCounts[.taper], 2)

        // Down weeks every 4th building week.
        XCTAssertEqual(plan.weeks.filter(\.isDownWeek).map(\.index), [3, 7, 11])

        // Volume ramps from current volume and respects the HM cap.
        XCTAssertEqual(plan.weeks[0].targetVolumeKm, 40, accuracy: 0.2)
        let peak = plan.weeks.map(\.targetVolumeKm).max()!
        XCTAssertGreaterThan(peak, 45)
        XCTAssertLessThanOrEqual(peak, 80)

        // 4 run days → exactly one non-long quality session per full building week.
        for week in plan.weeks where !week.isPartial && week.phase != .taper {
            let quality = week.workouts.filter { $0.kind == .tempo || $0.kind == .intervals }
            XCTAssertEqual(quality.count, 1, "week \(week.index)")
            let longs = week.workouts.filter { $0.kind == .long }
            XCTAssertEqual(longs.count, 1, "week \(week.index)")
        }

        // Race workout on race day at goal pace.
        let races = plan.weeks.flatMap(\.workouts).filter { $0.kind == .race }
        XCTAssertEqual(races.count, 1)
        XCTAssertEqual(races.first?.date, calendar.startOfDay(for: fixtureGoal.raceDate))

        XCTAssertTrue(PlanValidator.validate(plan, calendar: calendar).isEmpty)
    }

    func testMidWeekStartProratesPartialFirstWeek() {
        let today = PlanEngineTestSupport.date(2026, 1, 7) // Wednesday
        let plan = PlanGenerator.generate(
            goal: fixtureGoal, fitness: fixtureFitness, today: today, calendar: calendar
        )
        let first = plan.weeks[0]
        XCTAssertTrue(first.isPartial)
        // Thu/Sat/Sun remain of 4 run days → 75% of the 40 km week.
        XCTAssertEqual(first.targetVolumeKm, 30, accuracy: 0.2)
        XCTAssertTrue(first.workouts.allSatisfy { $0.date >= calendar.startOfDay(for: today) })
        XCTAssertTrue(PlanValidator.validate(plan, calendar: calendar).isEmpty)
    }

    func testImminentRaceProducesRaceWeekOnly() {
        let today = PlanEngineTestSupport.date(2026, 4, 15) // Wednesday before the race
        let plan = PlanGenerator.generate(
            goal: fixtureGoal, fitness: fixtureFitness, today: today, calendar: calendar
        )
        XCTAssertEqual(plan.weeks.count, 1)
        let kinds = plan.weeks[0].workouts.map(\.kind)
        XCTAssertTrue(kinds.contains(.race))
        XCTAssertFalse(kinds.contains(.long))
        XCTAssertFalse(kinds.contains(.tempo))
        XCTAssertTrue(PlanValidator.validate(plan, calendar: calendar).isEmpty)
    }

    func testPastRaceYieldsEmptyPlan() {
        let plan = PlanGenerator.generate(
            goal: fixtureGoal,
            fitness: fixtureFitness,
            today: PlanEngineTestSupport.date(2026, 5, 1),
            calendar: calendar
        )
        XCTAssertTrue(plan.weeks.isEmpty)
    }

    func testQualityWeekdaysRespectSpacingFromLongRun() {
        // Long Sunday: Saturday and Monday are too close (circular distance 1).
        let picked = PlanGenerator.qualityWeekdays(
            available: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday],
            longRunDay: .sunday,
            count: 2
        )
        XCTAssertEqual(picked.count, 2)
        for day in picked {
            XCTAssertGreaterThanOrEqual(PlanGenerator.circularDayDistance(day, .sunday), 2)
        }
        XCTAssertGreaterThanOrEqual(PlanGenerator.circularDayDistance(picked[0], picked[1]), 2)
    }

    func testQualityDroppedWhenSpacingImpossible() {
        // Three consecutive days: only one hard day fits besides the long run.
        let picked = PlanGenerator.qualityWeekdays(
            available: [.monday, .tuesday, .wednesday],
            longRunDay: .monday,
            count: 2
        )
        XCTAssertEqual(picked, [.wednesday])
    }
}
