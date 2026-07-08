import XCTest
@testable import TrainOrRest

final class WorkoutStructureTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    private var paces: TrainingPaces {
        VDOTTable.trainingPaces(vdot: 48)
    }

    private var plan: TrainingPlanSpec {
        PlanGenerator.generate(
            goal: GoalSpec(
                distance: .halfMarathon,
                targetTimeSeconds: 105 * 60,
                raceDate: PlanEngineTestSupport.date(2026, 4, 19),
                availableDays: [.tuesday, .thursday, .saturday, .sunday],
                longRunDay: .sunday
            ),
            fitness: FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0.05, longestRecentRunKm: 16),
            today: PlanEngineTestSupport.date(2026, 1, 5),
            calendar: calendar
        )
    }

    func testEasyAndLongRunsHaveSingleWorkStep() {
        let workouts = plan.weeks.flatMap(\.workouts)
        let easy = workouts.first { $0.kind == .easy }!
        let long = workouts.first { $0.kind == .long }!

        for workout in [easy, long] {
            XCTAssertEqual(workout.structure.count, 1)
            XCTAssertEqual(workout.structure[0].repeatCount, 1)
            XCTAssertEqual(workout.structure[0].steps.map(\.role), [.work])
            XCTAssertEqual(
                WorkoutStructure.totalDistanceKm(workout.structure),
                workout.distanceKm,
                accuracy: 0.05
            )
        }
        XCTAssertEqual(easy.details, "Easy run at E pace")
        XCTAssertEqual(long.details, "Long run at E pace")
    }

    func testTempoStructureMatchesRenderedDetailsAndDistance() {
        let tempo = plan.weeks.flatMap(\.workouts).first { $0.kind == .tempo }!

        XCTAssertEqual(tempo.structure.map(\.repeatCount), [1, 1, 1])
        XCTAssertEqual(tempo.structure.flatMap(\.steps).map(\.role), [.warmUp, .work, .coolDown])
        XCTAssertEqual(tempo.structure[0].steps[0].distanceKm, 2)
        XCTAssertEqual(tempo.structure[2].steps[0].distanceKm, 2)
        XCTAssertEqual(WorkoutProse.details(for: .tempo, structure: tempo.structure), tempo.details)
        XCTAssertEqual(WorkoutStructure.totalDistanceKm(tempo.structure), tempo.distanceKm, accuracy: 0.05)
    }

    func testIntervalsStructureKeepsRepeatBlock() {
        let intervals = plan.weeks.flatMap(\.workouts).first { $0.kind == .intervals }!
        let repeatGroup = intervals.structure[1]

        XCTAssertEqual(intervals.structure.count, 3)
        XCTAssertGreaterThanOrEqual(repeatGroup.repeatCount, 3)
        XCTAssertEqual(repeatGroup.steps.map(\.role), [.work, .recovery])
        XCTAssertEqual(repeatGroup.steps[0].distanceKm, 1)
        XCTAssertEqual(repeatGroup.steps[1].durationSeconds, 150)
        XCTAssertEqual(WorkoutProse.details(for: .intervals, structure: intervals.structure), intervals.details)
        XCTAssertEqual(WorkoutStructure.totalDistanceKm(intervals.structure), intervals.distanceKm, accuracy: 0.05)
    }

    func testStructuredDurationUsesPerStepPace() {
        let tempoKm = 5.0
        let structure = [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .warmUp, distanceKm: 2, paceBand: paces.easy)
            ]),
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .work, distanceKm: tempoKm, paceBand: paces.threshold)
            ]),
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .coolDown, distanceKm: 2, paceBand: paces.easy)
            ])
        ]

        let structuredDuration = WorkoutStructure.estimatedDurationSeconds(structure)
        let topLevelBand = paces.threshold
        let topLevelEstimate = (tempoKm + 4) * (topLevelBand.fastSecondsPerKm + topLevelBand.slowSecondsPerKm) / 2

        XCTAssertGreaterThan(structuredDuration, topLevelEstimate)
    }

    func testPlannedWorkoutPersistsStructureFromSpec() {
        let workout = plan.weeks.flatMap(\.workouts).first { $0.kind == .tempo }!
        let row = PlannedWorkout(spec: workout, weekIndex: 0, phase: .base)

        XCTAssertEqual(row.structure, workout.structure)
    }
}
