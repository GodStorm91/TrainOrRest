import XCTest
@testable import TrainOrRest

final class PushReconcilerTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 9)
    private let easyPace = PaceBand(fastSecondsPerKm: 360, slowSecondsPerKm: 390)

    func testDesiredEventsIncludeCurrentSevenDayWindow() {
        let todayWorkout = workout(date: today, uuid: uuid(1))
        let daySixWorkout = workout(
            date: calendar.date(byAdding: .day, value: 6, to: today)!,
            uuid: uuid(2)
        )
        let daySevenWorkout = workout(
            date: calendar.date(byAdding: .day, value: 7, to: today)!,
            uuid: uuid(3)
        )

        let desired = PushReconciler.desiredEvents(
            from: [todayWorkout, daySixWorkout, daySevenWorkout],
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(desired.map(\.externalID), [
            WorkoutDSL.externalID(for: uuid(1)),
            WorkoutDSL.externalID(for: uuid(2)),
        ])
    }

    func testDesiredEventsExcludeRaceEmptyDoneAndSkippedWorkouts() {
        let planned = workout(date: today, uuid: uuid(1))
        let race = workout(date: today, kind: .race, uuid: uuid(2))
        let empty = workout(date: today, uuid: uuid(3), structure: [])
        let done = workout(date: today, uuid: uuid(4), status: .done)
        let skipped = workout(date: today, uuid: uuid(5), status: .skipped)

        let desired = PushReconciler.desiredEvents(
            from: [planned, race, empty, done, skipped],
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(desired.map(\.externalID), [WorkoutDSL.externalID(for: uuid(1))])
    }

    func testReconcileUpsertsEveryDesiredEvent() {
        let local = [
            event(externalID: "trainorrest-a"),
            event(externalID: "trainorrest-b"),
        ]
        let remote = [
            RemoteWorkoutEvent(id: 1, externalID: "trainorrest-a")
        ]

        let plan = PushReconciler.reconcile(desiredEvents: local, remoteEvents: remote)

        XCTAssertEqual(plan.toUpsert, local)
        XCTAssertTrue(plan.toDelete.isEmpty)
    }

    func testReconcileDeletesOnlyOrphanedTrainOrRestEvents() {
        let local = [event(externalID: "trainorrest-a")]
        let remote = [
            RemoteWorkoutEvent(id: 1, externalID: "trainorrest-a"),
            RemoteWorkoutEvent(id: 2, externalID: "trainorrest-old"),
            RemoteWorkoutEvent(id: 3, externalID: "manual-event"),
            RemoteWorkoutEvent(id: 4, externalID: nil),
        ]

        let plan = PushReconciler.reconcile(desiredEvents: local, remoteEvents: remote)

        XCTAssertEqual(plan.toDelete, [2])
    }

    func testDesiredEventsUseStructuredMovingTime() {
        let structure = [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .warmUp, distanceKm: 1, paceBand: easyPace)
            ]),
            WorkoutStepGroup(repeatCount: 2, steps: [
                WorkoutStep(role: .work, distanceKm: 1, paceBand: easyPace),
                WorkoutStep(role: .recovery, durationSeconds: 90, paceBand: easyPace)
            ])
        ]
        let localWorkout = workout(date: today, uuid: uuid(1), structure: structure)

        let desired = PushReconciler.desiredEvents(from: [localWorkout], today: today, calendar: calendar)

        XCTAssertEqual(desired.first?.movingTime, WorkoutDSL.movingTimeSeconds(structure))
    }

    private func workout(
        date: Date,
        kind: WorkoutKind = .easy,
        uuid: UUID,
        status: WorkoutStatus = .planned,
        structure: [WorkoutStepGroup]? = nil
    ) -> PlannedWorkout {
        let structure = structure ?? [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .work, distanceKm: 10, paceBand: easyPace)
            ])
        ]
        let spec = PlannedWorkoutSpec(
            date: date,
            kind: kind,
            distanceKm: WorkoutStructure.totalDistanceKm(structure),
            paceBand: easyPace,
            details: "Run",
            structure: structure
        )
        let workout = PlannedWorkout(spec: spec, weekIndex: 0, phase: .base)
        workout.uuid = uuid
        workout.status = status
        return workout
    }

    private func event(externalID: String) -> IntervalsWorkoutEvent {
        IntervalsWorkoutEvent(
            externalID: externalID,
            startDateLocal: "2026-07-09T00:00:00",
            name: "Run",
            description: "- 10km 6:30-6:00/km Pace",
            movingTime: 3900
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
