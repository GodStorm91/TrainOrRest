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

    // MARK: - Shared factory

    /// The generator and the coach build workouts through the same factory, so
    /// the generator's output must equal the canonical recipes exactly.
    func testGeneratorOutputMatchesCanonicalFactory() {
        let workouts = plan.weeks.flatMap(\.workouts)
        let tempo = workouts.first { $0.kind == .tempo }!
        let intervals = workouts.first { $0.kind == .intervals }!
        let easy = workouts.first { $0.kind == .easy }!

        let workKm = tempo.structure.flatMap(\.steps).first { $0.role == .work }!.distanceKm!
        let reps = intervals.structure.first { $0.repeatCount > 1 }!.repeatCount

        let canonicalTempo = WorkoutFactory.canonicalTempo(tempoKm: workKm, paces: paces)
        let canonicalIntervals = WorkoutFactory.canonicalIntervals(repCount: reps, paces: paces)
        let canonicalEasy = WorkoutFactory.canonicalEasy(distanceKm: easy.distanceKm, paces: paces)

        XCTAssertEqual(canonicalTempo.structure, tempo.structure)
        XCTAssertEqual(canonicalTempo.distanceKm, tempo.distanceKm, accuracy: 0.001)
        XCTAssertEqual(canonicalTempo.details, tempo.details)
        XCTAssertEqual(canonicalTempo.paceBand, tempo.paceBand)

        XCTAssertEqual(canonicalIntervals.structure, intervals.structure)
        XCTAssertEqual(canonicalIntervals.distanceKm, intervals.distanceKm, accuracy: 0.001)
        XCTAssertEqual(canonicalIntervals.details, intervals.details)

        XCTAssertEqual(canonicalEasy.structure, easy.structure)
        XCTAssertEqual(canonicalEasy.details, easy.details)
    }

    /// A model may only choose shape and zone; the app supplies every pace.
    func testFactoryResolvesZonesFromAppFitness() throws {
        let recipe = WorkoutRecipe(kind: .intervals, blocks: [
            .init(repeatCount: 1, steps: [.distance(.warmUp, 2, .easy)]),
            .init(repeatCount: 4, steps: [
                .distance(.work, 1, .interval),
                .duration(.recovery, 90, .easy)
            ]),
            .init(repeatCount: 1, steps: [.distance(.coolDown, 2, .easy)])
        ])

        let built = try WorkoutFactory.build(recipe, paces: paces)

        XCTAssertEqual(built.paceBand, paces.interval)
        XCTAssertEqual(built.structure[1].steps[0].paceBand, paces.interval)
        XCTAssertEqual(built.structure[1].steps[1].paceBand, paces.easy)
        XCTAssertEqual(built.distanceKm, 8, accuracy: 0.001) // 2 + 4×1 + 2
        XCTAssertEqual(built.details, "2 km warm-up · 4 × 1 km at I pace (1:30 jog) · 2 km cool-down")
    }

    func testFactoryRejectsUnsafeOrIncoherentRecipes() {
        let cases: [(String, WorkoutRecipe, TrainingPaces?)] = [
            ("race", WorkoutRecipe(kind: .race, blocks: [.init(repeatCount: 1, steps: [.distance(.work, 5, .easy)])]), paces),
            ("tempo work at easy pace", WorkoutFactory.tempoRecipe(tempoKm: 5).replacingWorkZone(.easy), paces),
            ("quality without fitness", WorkoutFactory.tempoRecipe(tempoKm: 5), nil),
            ("zero target", WorkoutRecipe(kind: .easy, blocks: [.init(repeatCount: 1, steps: [.distance(.work, 0, .easy)])]), paces),
            ("distance over cap", WorkoutRecipe(kind: .easy, blocks: [.init(repeatCount: 1, steps: [.distance(.work, 500, .easy)])]), paces),
            ("repeat over cap", WorkoutRecipe(kind: .easy, blocks: [.init(repeatCount: 99, steps: [.distance(.work, 1, .easy)])]), paces)
        ]
        for (name, recipe, paces) in cases {
            XCTAssertThrowsError(try WorkoutFactory.build(recipe, paces: paces), "\(name) must be rejected")
        }
    }

    /// Easy and long stay unpaced rather than failing when fitness is unknown.
    func testEasyRunBuildsWithoutFitness() throws {
        let built = try WorkoutFactory.build(WorkoutFactory.singleRun(kind: .easy, distanceKm: 6), paces: nil)
        XCTAssertNil(built.paceBand)
        XCTAssertEqual(built.distanceKm, 6, accuracy: 0.001)
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

private extension WorkoutRecipe {
    /// Bends a canonical recipe into an invalid one for rejection tests.
    func replacingWorkZone(_ zone: PaceZone) -> WorkoutRecipe {
        var copy = self
        copy.blocks = copy.blocks.map { block in
            var block = block
            block.steps = block.steps.map { step in
                var step = step
                if step.role == .work { step.zone = zone }
                return step
            }
            return block
        }
        return copy
    }
}
