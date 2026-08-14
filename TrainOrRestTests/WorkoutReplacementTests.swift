import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class WorkoutReplacementTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let occupiedDay = PlanEngineTestSupport.date(2026, 1, 7, hour: 0)

    func testStagingOccupiedWorkoutReplacementDoesNotPersist() throws {
        let container = try makeContainer()
        let pending = try pendingReplacement(in: container.mainContext)
        let before = try snapshot(in: ModelContext(container))
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })

        coordinator.stage(pending)

        XCTAssertEqual(coordinator.pending, pending)
        XCTAssertEqual(try snapshot(in: ModelContext(container)), before)
        XCTAssertTrue(try messages(in: ModelContext(container)).isEmpty)
    }

    /// The plan-update card renders these fields, so they must describe the real
    /// before/after workouts and the real change to the week's target volume.
    func testStagedReplacementCarriesRealBeforeAfterAndVolumeDelta() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))
        let existingKind = try XCTUnwrap(existing.kind)
        let existingDistance = existing.distanceKm

        let pending = try pendingReplacement(in: context)

        XCTAssertEqual(pending.existing.kind, existingKind)
        XCTAssertEqual(pending.existing.distanceKm, existingDistance, accuracy: 0.001)
        XCTAssertEqual(
            pending.volumeDeltaKm,
            pending.proposed.distanceKm - pending.existing.distanceKm,
            accuracy: 0.051,
            "the card's footer delta must match what the engine applies to the week target"
        )
    }

    func testConfirmationPreservesIdentityReplacesFieldsAndWritesAudit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))
        existing.matchedActivityUUID = UUID()
        try context.save()
        let pending = try pendingReplacement(in: context)
        let oldID = existing.uuid
        let oldDetails = existing.details
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })

        coordinator.stage(pending)
        coordinator.confirm(pending.id)

        let verification = ModelContext(container)
        let replaced = try XCTUnwrap(workout(on: occupiedDay, in: verification))
        XCTAssertEqual(replaced.uuid, oldID)
        XCTAssertEqual(replaced.kind, .easy)
        XCTAssertEqual(replaced.distanceKm, 5, accuracy: 0.001)
        XCTAssertNotEqual(replaced.details, oldDetails)
        XCTAssertEqual(replaced.structure.flatMap(\.steps).map(\.role), [.work])
        XCTAssertNil(replaced.paceBand)
        XCTAssertEqual(replaced.status, .planned)
        XCTAssertTrue(replaced.manuallyOverridden)
        XCTAssertNil(replaced.matchedActivityUUID)

        let audit = try XCTUnwrap(messages(in: verification).first)
        XCTAssertEqual(audit.role, .assistant)
        XCTAssertEqual(audit.text, pending.successMessage)
        XCTAssertEqual(audit.appliedAdjustment, pending.appliedSummary)
    }

    func testCancelledConfirmationWritesNothing() throws {
        let container = try makeContainer()
        let pending = try pendingReplacement(in: container.mainContext)
        let before = try snapshot(in: ModelContext(container))
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })

        coordinator.stage(pending)
        coordinator.cancel()
        coordinator.confirm(pending.id)

        XCTAssertNil(coordinator.pending)
        XCTAssertEqual(try snapshot(in: ModelContext(container)), before)
        XCTAssertTrue(try messages(in: ModelContext(container)).isEmpty)
    }

    func testStaleConfirmationWritesNoAdditionalChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = try pendingReplacement(in: context)
        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))
        existing.details = "Changed after confirmation was offered"
        try context.save()
        let before = try snapshot(in: ModelContext(container))
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })

        coordinator.stage(pending)
        coordinator.confirm(pending.id)

        XCTAssertEqual(coordinator.lastError, pending.failureMessage)
        XCTAssertEqual(try snapshot(in: ModelContext(container)), before)
        XCTAssertTrue(try messages(in: ModelContext(container)).isEmpty)
    }

    private func pendingReplacement(in context: ModelContext) throws -> PendingWorkoutReplacement {
        let workout = PlanAdjustmentProposal.CreateWorkout(
            kind: "easy",
            blocks: [.init(repeatCount: 1, steps: [.init(
                role: "work", targetType: "distance_km", targetValue: 5, paceZone: "easy"
            )])]
        )
        let proposal = PlanAdjustmentProposal(changes: [.init(
            date: CoachContextBuilder.day(occupiedDay, calendar: calendar),
            action: .create, detail: nil, workout: workout
        )])
        return try XCTUnwrap(try CoachTools.pendingReplacement(
            for: proposal, in: context, today: today, calendar: calendar, language: .en
        ))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self, Goal.self,
            TrainingPlan.self, PlannedWorkout.self, DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatMessage.self
        ])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let goal = GoalSpec(
            distance: .halfMarathon, targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 1, 25),
            availableDays: Set(Weekday.allCases), longRunDay: .sunday
        )
        let fitness = FitnessProfile(vdot: 44, weeklyVolumeKm: 30, volumeTrend: 0, longestRecentRunKm: 12)
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: container.mainContext)
        return container
    }

    private func workout(on date: Date, in context: ModelContext) throws -> PlannedWorkout? {
        try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    private func messages(in context: ModelContext) throws -> [ChatMessage] {
        try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
    }

    private func snapshot(in context: ModelContext) throws -> [Row] {
        try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)])).map {
            Row(id: $0.uuid, kind: $0.kindRaw, distance: $0.distanceKm, details: $0.details,
                overridden: $0.manuallyOverridden, matched: $0.matchedActivityUUID)
        }
    }

    private struct Row: Equatable {
        let id: UUID
        let kind: String
        let distance: Double
        let details: String
        let overridden: Bool
        let matched: UUID?
    }
}
