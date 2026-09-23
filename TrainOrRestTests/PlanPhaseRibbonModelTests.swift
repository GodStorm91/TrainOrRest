import XCTest
@testable import TrainOrRest

final class PlanPhaseRibbonModelTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    func testBuildsPlanAlignedPhaseSegmentsAndDownWeekTicks() throws {
        let anchor = PlanEngineTestSupport.date(2026, 8, 5)
        let weekZero = PlanGenerator.mondayOfWeek(containing: anchor, calendar: calendar)
        let phases: [TrainingPhase] = [.base, .base, .build, .build, .build, .build, .peak, .peak, .taper]
        let goalSpec = GoalSpec(
            distance: .marathon,
            targetTimeSeconds: 4 * 3600,
            raceDate: calendar.date(byAdding: .day, value: 120, to: weekZero)!,
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday
        )
        let plan = TrainingPlan(spec: TrainingPlanSpec(
            goal: goalSpec,
            anchorDate: anchor,
            weeks: phases.enumerated().map { index, phase in
                WeekPlan(
                    startDate: calendar.date(byAdding: .day, value: index * 7, to: weekZero)!,
                    index: index,
                    phase: phase,
                    isDownWeek: index == 4,
                    isPartial: false,
                    targetVolumeKm: 30 + Double(index),
                    workouts: []
                )
            }
        ), generatedAt: anchor)
        let goal = Goal(spec: goalSpec, createdAt: anchor)
        let today = calendar.date(byAdding: .day, value: 3 * 7, to: weekZero)!
        let summary = try XCTUnwrap(ActivePlanSummaryBuilder.build(
            goal: goal,
            plan: plan,
            activities: [],
            today: today,
            calendar: calendar
        ))
        let model = try XCTUnwrap(PlanPhaseRibbonModel(plan: plan, summary: summary, calendar: calendar))

        XCTAssertEqual(model.segments.map(\.weekCount), [2, 4, 2, 1])
        XCTAssertEqual(model.currentWeekIndex, 3)

        let build = try XCTUnwrap(model.segments.first(where: { $0.phase == .build }))
        XCTAssertEqual(build.currentWeekInSegment, 2)
        XCTAssertEqual(build.weekCount, 4)
        XCTAssertEqual(model.activeSegmentID, build.id)
        XCTAssertEqual(build.ticks.filter(\.isDown).map(\.weekIndex), [4])

        let modelWeekZero = try XCTUnwrap(model.weekStart(for: 0))
        XCTAssertEqual(modelWeekZero, weekZero)
        XCTAssertEqual(calendar.component(.weekday, from: modelWeekZero), 2)
    }
}
