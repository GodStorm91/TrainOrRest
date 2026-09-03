import XCTest
@testable import TrainOrRest

final class WorkoutDSLTests: XCTestCase {
    private let easyPace = PaceBand(fastSecondsPerKm: 360, slowSecondsPerKm: 390)
    private let thresholdPace = PaceBand(fastSecondsPerKm: 270, slowSecondsPerKm: 285)
    private let intervalPace = PaceBand(fastSecondsPerKm: 250, slowSecondsPerKm: 265)

    func testEasyRunRendersSinglePacedStep() {
        let structure = [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .work, distanceKm: 10, paceBand: easyPace)
            ])
        ]

        XCTAssertEqual(
            WorkoutDSL.render(kind: .easy, structure: structure),
            "- 10km 6:30-6:00/km Pace"
        )
        XCTAssertEqual(WorkoutDSL.eventName(kind: .easy, structure: structure), "Easy Run - 10km")
    }

    func testTempoRunRendersWarmupTempoCooldownSections() {
        let structure = [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .warmUp, distanceKm: 2, paceBand: easyPace)
            ]),
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .work, distanceKm: 5, paceBand: thresholdPace)
            ]),
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .coolDown, distanceKm: 2, paceBand: easyPace)
            ])
        ]

        XCTAssertEqual(
            WorkoutDSL.render(kind: .tempo, structure: structure),
            """
            Warmup
            - 2km 6:30-6:00/km Pace

            Tempo
            - 5km 4:45-4:30/km Pace

            Cooldown
            - 2km 6:30-6:00/km Pace
            """
        )
        XCTAssertEqual(WorkoutDSL.eventName(kind: .tempo, structure: structure), "Tempo - 5km @ T pace")
    }

    func testIntervalsRunRendersRepeatHeaderAndRecoveryDuration() {
        let structure = [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .warmUp, distanceKm: 2, paceBand: easyPace)
            ]),
            WorkoutStepGroup(repeatCount: 3, steps: [
                WorkoutStep(role: .work, distanceKm: 1, paceBand: intervalPace),
                WorkoutStep(role: .recovery, durationSeconds: 150, paceBand: easyPace)
            ]),
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .coolDown, distanceKm: 2, paceBand: easyPace)
            ])
        ]

        XCTAssertEqual(
            WorkoutDSL.render(kind: .intervals, structure: structure),
            """
            Warmup
            - 2km 6:30-6:00/km Pace

            Main set 3x
            - 1km 4:25-4:10/km Pace
            - 2m30 6:30-6:00/km Pace

            Cooldown
            - 2km 6:30-6:00/km Pace
            """
        )
        XCTAssertEqual(WorkoutDSL.eventName(kind: .intervals, structure: structure), "Intervals - 3 x 1km @ I pace")
    }

    func testUnpacedStepFallsBackToEasyPaceAndEqualBandRenders() {
        // A step with no fitness-derived band must still push a pace target
        // (the fallback easy band) so the watch never shows distance-only.
        let structure = [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .work, distanceKm: 1.25),
                WorkoutStep(
                    role: .recovery,
                    durationSeconds: 45,
                    paceBand: PaceBand(fastSecondsPerKm: 300, slowSecondsPerKm: 300)
                )
            ])
        ]

        XCTAssertEqual(
            WorkoutDSL.render(kind: .intervals, structure: structure),
            """
            Main set
            - 1.25km 6:30-6:00/km Pace
            - 45s 5:00-5:00/km Pace
            """
        )
    }

    func testEasyRunWithoutFitnessStillPushesAPaceTarget() throws {
        // Easy/long runs built while current fitness is unavailable have no band;
        // the pushed workout must still carry a pace, not just the distance.
        let spec = PlannedWorkoutSpec(
            date: PlanEngineTestSupport.date(2026, 7, 10),
            kind: .easy,
            distanceKm: 8,
            paceBand: nil,
            details: "Easy run",
            structure: WorkoutStructure.run(distanceKm: 8, paceBand: nil)
        )
        let workout = PlannedWorkout(spec: spec, weekIndex: 1, phase: .base)

        let event = try XCTUnwrap(WorkoutDSL.event(for: workout, calendar: PlanEngineTestSupport.calendar))
        XCTAssertEqual(event.description, "- 8km 6:30-6:00/km Pace")
    }

    func testMovingTimeUsesStructuredDuration() {
        let structure = [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .warmUp, distanceKm: 1, paceBand: easyPace)
            ]),
            WorkoutStepGroup(repeatCount: 2, steps: [
                WorkoutStep(role: .work, distanceKm: 1, paceBand: thresholdPace),
                WorkoutStep(role: .recovery, durationSeconds: 150, paceBand: easyPace)
            ])
        ]

        XCTAssertEqual(
            WorkoutDSL.movingTimeSeconds(structure),
            Int(WorkoutStructure.estimatedDurationSeconds(structure).rounded())
        )
    }

    func testPlannedWorkoutBuildsPushEventPayload() throws {
        let spec = PlannedWorkoutSpec(
            date: PlanEngineTestSupport.date(2026, 7, 10),
            kind: .easy,
            distanceKm: 10,
            paceBand: easyPace,
            details: "Easy run",
            structure: [
                WorkoutStepGroup(steps: [
                    WorkoutStep(role: .work, distanceKm: 10, paceBand: easyPace)
                ])
            ]
        )
        let workout = PlannedWorkout(spec: spec, weekIndex: 1, phase: .base)

        let event = try XCTUnwrap(WorkoutDSL.event(for: workout, calendar: PlanEngineTestSupport.calendar))

        XCTAssertEqual(event.externalID, WorkoutDSL.externalID(for: workout.uuid))
        XCTAssertTrue(event.externalID.hasPrefix("trainorrest-"))
        XCTAssertEqual(event.startDateLocal, "2026-07-10T00:00:00")
        XCTAssertEqual(event.category, "WORKOUT")
        XCTAssertEqual(event.type, "Run")
        XCTAssertEqual(event.name, "Easy Run - 10km")
        XCTAssertEqual(event.description, "- 10km 6:30-6:00/km Pace")
        XCTAssertEqual(event.movingTime, WorkoutDSL.movingTimeSeconds(spec.structure))
    }

    func testRaceWorkoutDoesNotBuildPushEventPayload() {
        let spec = PlannedWorkoutSpec(
            date: PlanEngineTestSupport.date(2026, 7, 10),
            kind: .race,
            distanceKm: 21.1,
            paceBand: thresholdPace,
            details: "Race day",
            structure: [
                WorkoutStepGroup(steps: [
                    WorkoutStep(role: .work, distanceKm: 21.1, paceBand: thresholdPace)
                ])
            ]
        )
        let workout = PlannedWorkout(spec: spec, weekIndex: 1, phase: .peak)

        XCTAssertNil(WorkoutDSL.event(for: workout, calendar: PlanEngineTestSupport.calendar))
    }
}
