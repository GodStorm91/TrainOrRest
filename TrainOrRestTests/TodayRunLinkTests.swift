import XCTest
@testable import TrainOrRest

final class TodayRunLinkTests: XCTestCase {
    private let today = PlanEngineTestSupport.date(2026, 1, 5)

    func testSuggestedWorkoutTakesPrecedenceOverOtherStates() {
        let planned = makeWorkout(status: .planned)
        let linked = makeWorkout(status: .done)
        let linkedRun = makeRun(hour: 6)
        linked.matchedActivityUUID = linkedRun.hkUUID
        let candidate = makeRun(hour: 7)

        let result = TodayRunLink.resolve(
            workouts: [linked, planned], activities: [linkedRun, candidate]
        )

        XCTAssertEqual(result, .suggested(planned, candidate))
    }

    func testPendingWorkoutTakesPrecedenceOverLinkedWorkout() {
        let pending = makeWorkout(status: .planned)
        pending.dismissLink(UUID())
        let linked = makeWorkout(status: .done)
        let run = makeRun(hour: 7)
        linked.matchedActivityUUID = run.hkUUID

        let result = TodayRunLink.resolve(workouts: [pending, linked], activities: [run])

        XCTAssertEqual(result, .pending(pending))
    }

    func testLinkedWorkoutTakesPrecedenceOverDoneWithoutRunAndSkipped() {
        let missingRun = makeWorkout(status: .done)
        let linked = makeWorkout(status: .done)
        let skipped = makeWorkout(status: .skipped)
        let run = makeRun(hour: 7)
        linked.matchedActivityUUID = run.hkUUID

        let result = TodayRunLink.resolve(workouts: [missingRun, linked, skipped], activities: [run])

        XCTAssertEqual(result, .linked(linked, run))
    }

    func testDoneWithoutRunTakesPrecedenceOverSkippedWorkout() {
        let done = makeWorkout(status: .done)
        let skipped = makeWorkout(status: .skipped)

        let result = TodayRunLink.resolve(workouts: [done, skipped], activities: [])

        XCTAssertEqual(result, .doneWithoutRun(done))
    }

    func testUnplannedRunUsesLatestActivityAndOtherwiseRest() {
        let earlier = makeRun(hour: 6)
        let later = makeRun(hour: 18)

        XCTAssertEqual(
            TodayRunLink.resolve(workouts: [], activities: [earlier, later]),
            .unplannedRun(later)
        )
        XCTAssertEqual(TodayRunLink.resolve(workouts: [], activities: []), .rest)
    }

    private func makeWorkout(status: WorkoutStatus) -> PlannedWorkout {
        let workout = PlannedWorkout(
            spec: PlannedWorkoutSpec(
                date: today,
                kind: .easy,
                distanceKm: 8,
                paceBand: PaceBand(fastSecondsPerKm: 300, slowSecondsPerKm: 360),
                details: "Easy run"
            ),
            weekIndex: 0,
            phase: .base
        )
        workout.status = status
        return workout
    }

    private func makeRun(hour: Int) -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: PlanEngineTestSupport.date(2026, 1, 5, hour: hour),
            distanceMeters: 8_000,
            durationSeconds: 48 * 60,
            avgHeartRate: 145,
            maxHeartRate: 165,
            avgPaceSecondsPerKm: 360,
            sourceName: "Test"
        )
    }
}
