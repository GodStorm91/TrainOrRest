import XCTest
@testable import TrainOrRest

final class FeasibilityCheckTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let raceDate = PlanEngineTestSupport.date(2026, 4, 19) // ~15 weeks out

    private func goal(_ distance: RaceDistance, timeSeconds: Double) -> GoalSpec {
        GoalSpec(
            distance: distance,
            targetTimeSeconds: timeSeconds,
            raceDate: raceDate,
            availableDays: [.tuesday, .thursday, .sunday],
            longRunDay: .sunday
        )
    }

    private func fitness(vdot: Double, volume: Double = 40) -> FitnessProfile {
        FitnessProfile(vdot: vdot, weeklyVolumeKm: volume, volumeTrend: 0, longestRecentRunKm: 15)
    }

    func testGoalAtCurrentFitnessIsOk() {
        let time = VDOTTable.predictedTimeSeconds(distanceMeters: 10000, vdot: 48)
        let assessment = FeasibilityCheck.assess(
            goal: goal(.tenK, timeSeconds: time), fitness: fitness(vdot: 48), today: today, calendar: calendar
        )
        XCTAssertEqual(assessment.verdict, .ok)
    }

    func testGoalJustAboveProjectionIsStretch() {
        // ~15 weeks out the projection is 48 + 15×0.15 ≈ 50.2; a 52-VDOT goal
        // sits above it but within the 3-point stretch margin.
        let time = VDOTTable.predictedTimeSeconds(distanceMeters: 10000, vdot: 52)
        let assessment = FeasibilityCheck.assess(
            goal: goal(.tenK, timeSeconds: time), fitness: fitness(vdot: 48), today: today, calendar: calendar
        )
        XCTAssertEqual(assessment.verdict, .stretch)
        XCTAssertGreaterThan(assessment.goalVDOT, assessment.projectedVDOT)
    }

    func testMarathon230OnLowMileageIsUnrealistic() {
        // FM 2:30 (~VDOT 67) is far beyond what modest fitness can reach in one block.
        let assessment = FeasibilityCheck.assess(
            goal: goal(.marathon, timeSeconds: 2.5 * 3600),
            fitness: fitness(vdot: 42, volume: 20),
            today: today,
            calendar: calendar
        )
        XCTAssertEqual(assessment.verdict, .unrealistic)
        XCTAssertGreaterThan(assessment.goalVDOT, 60)
    }

    func testUnrealisticGoalStillGeneratesValidPlan() {
        let unrealistic = goal(.marathon, timeSeconds: 2.5 * 3600)
        let plan = PlanGenerator.generate(
            goal: unrealistic, fitness: fitness(vdot: 42, volume: 20), today: today, calendar: calendar
        )
        XCTAssertFalse(plan.weeks.isEmpty)
        XCTAssertTrue(PlanValidator.validate(plan, calendar: calendar).isEmpty)
    }
}
