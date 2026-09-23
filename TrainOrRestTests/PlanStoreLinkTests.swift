import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class PlanStoreLinkTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)

    func testAutoMatchLinksScheduleMovedWorkout() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = makeWorkout()
        workout.manuallyOverridden = true
        let run = makeRun()
        context.insert(workout)
        context.insert(run)
        try context.save()

        try PlanStore.autoMatch(in: context, calendar: calendar)

        XCTAssertEqual(workout.status, .done)
        XCTAssertEqual(workout.matchedActivityUUID, run.hkUUID)
        XCTAssertTrue(workout.manuallyOverridden)
    }

    func testUnlinkDismissesPairAndSurvivesNextAutoMatch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = makeWorkout()
        let run = makeRun()
        context.insert(workout)
        context.insert(run)
        try context.save()
        try PlanStore.autoMatch(in: context, calendar: calendar)

        try PlanStore.unlink(workout, in: context)
        try PlanStore.autoMatch(in: context, calendar: calendar)

        XCTAssertEqual(workout.status, .planned)
        XCTAssertNil(workout.matchedActivityUUID)
        XCTAssertTrue(workout.isLinkDismissed(run.hkUUID))
    }

    func testManualLinkClearsDismissalAndIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = makeWorkout()
        let run = makeRun()
        workout.dismissLink(run.hkUUID)
        context.insert(workout)
        context.insert(run)
        try context.save()

        try PlanStore.link(run, to: workout, in: context)
        try PlanStore.link(run, to: workout, in: context)

        XCTAssertEqual(workout.status, .done)
        XCTAssertEqual(workout.matchedActivityUUID, run.hkUUID)
        XCTAssertFalse(workout.isLinkDismissed(run.hkUUID))
        XCTAssertNil(workout.dismissedActivityUUIDs)
    }

    func testManualLinkNormalizesAlreadyMatchedDismissedState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = makeWorkout()
        let run = makeRun()
        workout.status = .planned
        workout.matchedActivityUUID = run.hkUUID
        workout.dismissLink(run.hkUUID)
        context.insert(workout)
        context.insert(run)
        try context.save()

        try PlanStore.link(run, to: workout, in: context)

        XCTAssertEqual(workout.status, .done)
        XCTAssertEqual(workout.matchedActivityUUID, run.hkUUID)
        XCTAssertTrue(workout.manuallyOverridden)
        XCTAssertFalse(workout.isLinkDismissed(run.hkUUID))
    }

    func testDismissSuggestionPersistsWithoutChangingPlanStatus() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = makeWorkout()
        let run = makeRun()
        context.insert(workout)
        context.insert(run)
        try context.save()

        try PlanStore.dismissSuggestion(run, for: workout, in: context)

        XCTAssertEqual(workout.status, .planned)
        XCTAssertNil(workout.matchedActivityUUID)
        XCTAssertTrue(workout.isLinkDismissed(run.hkUUID))
    }

    func testLinkAndUnlinkCopyAndRevertPlannedShoe() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = makeWorkout()
        let run = makeRun()
        let shoeID = UUID()
        workout.shoeID = shoeID
        workout.shoeAssignmentSource = .planned
        context.insert(workout)
        context.insert(run)
        try context.save()

        try PlanStore.link(run, to: workout, in: context)

        XCTAssertEqual(run.shoeID, shoeID)
        XCTAssertEqual(run.shoeAssignmentSource, .planned)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShoeMileageEntry>()).count, 1)

        try PlanStore.unlink(workout, in: context)

        XCTAssertNil(run.shoeID)
        XCTAssertEqual(run.shoeAssignmentSource, .none)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShoeMileageEntry>()).isEmpty)
    }

    func testDismissedLinksDoNotDuplicateAndCanClear() throws {
        let workout = makeWorkout()
        let runID = UUID()

        workout.dismissLink(runID)
        workout.dismissLink(runID)
        XCTAssertEqual(workout.dismissedActivityUUIDs, [runID])

        workout.clearLinkDismissal(runID)

        XCTAssertNil(workout.dismissedActivityUUIDs)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PlannedWorkout.self, CompletedActivity.self, ShoeMileageEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func makeWorkout() -> PlannedWorkout {
        PlannedWorkout(
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
    }

    private func makeRun() -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: PlanEngineTestSupport.date(2026, 1, 5, hour: 7),
            distanceMeters: 8_000,
            durationSeconds: 48 * 60,
            avgHeartRate: 145,
            maxHeartRate: 165,
            avgPaceSecondsPerKm: 360,
            sourceName: "Test"
        )
    }
}
