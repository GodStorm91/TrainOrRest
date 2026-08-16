import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class PlanEditTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let occupiedDay = PlanEngineTestSupport.date(2026, 1, 7, hour: 0)

    func testCoachReplacementInsertsPlanEditWithBeforeState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))
        let matchedActivityUUID = UUID()
        existing.matchedActivityUUID = matchedActivityUUID
        try context.save()
        let beforeTarget = try weekTarget(existing.weekIndex, in: context)
        let beforeStructure = existing.structure
        let beforeKindRaw = existing.kindRaw
        let beforeDistance = existing.distanceKm
        let beforeDetails = existing.details
        let beforeStatusRaw = existing.statusRaw
        let beforeOverridden = existing.manuallyOverridden
        let pending = try pendingReplacement(in: context)

        try CoachTools.confirmReplacement(pending, in: context, today: today, calendar: calendar)

        let edit = try XCTUnwrap(try planEdits(in: context).first)
        XCTAssertEqual(edit.appliedAt, today)
        XCTAssertEqual(edit.workoutUUID, existing.uuid)
        XCTAssertTrue(calendar.isDate(edit.workoutDate, inSameDayAs: occupiedDay))
        XCTAssertEqual(edit.weekIndex, existing.weekIndex)
        XCTAssertEqual(edit.kindRaw, beforeKindRaw)
        XCTAssertEqual(edit.distanceKm, beforeDistance, accuracy: 0.001)
        XCTAssertEqual(edit.details, beforeDetails)
        XCTAssertEqual(edit.structure, beforeStructure)
        XCTAssertEqual(edit.statusRaw, beforeStatusRaw)
        XCTAssertEqual(edit.manuallyOverridden, beforeOverridden)
        XCTAssertEqual(edit.matchedActivityUUID, matchedActivityUUID)
        XCTAssertEqual(edit.weekTargetVolumeKmBefore, beforeTarget, accuracy: 0.001)
        XCTAssertEqual(edit.afterKindRaw, "easy")
        XCTAssertEqual(edit.afterDistanceKm, 5, accuracy: 0.001)
        XCTAssertNil(edit.afterPaceFastSecondsPerKm)
        XCTAssertNil(edit.afterPaceSlowSecondsPerKm)
        XCTAssertEqual(edit.afterDetails, "Easy run at E pace")
        XCTAssertEqual(edit.afterStructure.flatMap(\.steps).map(\.role), [.work])
        XCTAssertEqual(edit.afterStatusRaw, WorkoutStatus.planned.rawValue)
        XCTAssertTrue(edit.afterManuallyOverridden)
        XCTAssertNil(edit.afterMatchedActivityUUID)
        XCTAssertEqual(edit.weekTargetVolumeKmAfter, try weekTarget(existing.weekIndex, in: context), accuracy: 0.001)
        XCTAssertNil(edit.revertedAt)
        XCTAssertEqual(edit.source, "coach")
    }

    func testRevertRestoresWorkoutFieldsAndWeekTargetVolume() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))
        let matchedActivityUUID = UUID()
        existing.matchedActivityUUID = matchedActivityUUID
        try context.save()
        let before = WorkoutSnapshot(workout: existing)
        let beforeTarget = try weekTarget(existing.weekIndex, in: context)
        let pending = try pendingReplacement(in: context)
        try CoachTools.confirmReplacement(pending, in: context, today: today, calendar: calendar)
        let edit = try XCTUnwrap(try planEdits(in: context).first)

        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)

        let restored = try XCTUnwrap(workout(on: occupiedDay, in: context))
        XCTAssertEqual(WorkoutSnapshot(workout: restored), before)
        XCTAssertEqual(try weekTarget(existing.weekIndex, in: context), beforeTarget, accuracy: 0.001)
        XCTAssertEqual(edit.revertedAt, today)
    }

    func testRevertAfterSevenDaysIsRefused() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = try pendingReplacement(in: context)
        try CoachTools.confirmReplacement(pending, in: context, today: today, calendar: calendar)
        let edit = try XCTUnwrap(try planEdits(in: context).first)
        let tooLate = try XCTUnwrap(calendar.date(byAdding: .day, value: 8, to: today))

        XCTAssertThrowsError(try PlanEditStore.revert(edit.id, in: context, today: tooLate, calendar: calendar)) { error in
            XCTAssertEqual(error.localizedDescription, "Coach edits can only be reverted for 7 days.")
        }
        XCTAssertNil(edit.revertedAt)
    }

    func testRevertIsRefusedWhenWorkoutChangedAfterCoachEdit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = try pendingReplacement(in: context)
        try CoachTools.confirmReplacement(pending, in: context, today: today, calendar: calendar)
        let edit = try XCTUnwrap(try planEdits(in: context).first)
        let changed = try XCTUnwrap(workout(on: occupiedDay, in: context))
        changed.details = "Changed after coach edit"
        try context.save()

        XCTAssertThrowsError(try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)) { error in
            XCTAssertEqual(error.localizedDescription, PlanEditStore.changedAfterEditMessage)
        }
        XCTAssertNil(edit.revertedAt)
    }

    func testRevertIsRefusedWhenWorkoutMovedAfterCoachEdit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = try pendingReplacement(in: context)
        try CoachTools.confirmReplacement(pending, in: context, today: today, calendar: calendar)
        let edit = try XCTUnwrap(try planEdits(in: context).first)
        let moved = try XCTUnwrap(workout(on: occupiedDay, in: context))
        moved.date = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: moved.date))
        try context.save()

        XCTAssertThrowsError(try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)) { error in
            XCTAssertEqual(error.localizedDescription, PlanEditStore.changedAfterEditMessage)
        }
        XCTAssertNil(edit.revertedAt)
    }

    func testDoubleRevertIsRefused() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pending = try pendingReplacement(in: context)
        try CoachTools.confirmReplacement(pending, in: context, today: today, calendar: calendar)
        let edit = try XCTUnwrap(try planEdits(in: context).first)
        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)

        XCTAssertThrowsError(try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)) { error in
            XCTAssertEqual(error.localizedDescription, "That coach edit was already reverted.")
        }
        XCTAssertEqual(edit.revertedAt, today)
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
            TrainingPlan.self, PlannedWorkout.self, DailyReadiness.self, DailyCheckIn.self,
            RuleOverride.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self, PlanEdit.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let goal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 1, 25),
            availableDays: Set(Weekday.allCases),
            longRunDay: .sunday
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

    private func planEdits(in context: ModelContext) throws -> [PlanEdit] {
        try context.fetch(FetchDescriptor<PlanEdit>(sortBy: [SortDescriptor(\.appliedAt)]))
    }

    private func weekTarget(_ index: Int, in context: ModelContext) throws -> Double {
        let plan = try XCTUnwrap(PlanStore.activePlan(in: context))
        return plan.weekTargetVolumesKm[index]
    }

    private struct WorkoutSnapshot: Equatable {
        let kindRaw: String
        let distanceKm: Double
        let paceFastSecondsPerKm: Double?
        let paceSlowSecondsPerKm: Double?
        let details: String
        let structure: [WorkoutStepGroup]
        let statusRaw: String
        let manuallyOverridden: Bool
        let matchedActivityUUID: UUID?

        init(workout: PlannedWorkout) {
            kindRaw = workout.kindRaw
            distanceKm = workout.distanceKm
            paceFastSecondsPerKm = workout.paceFastSecondsPerKm
            paceSlowSecondsPerKm = workout.paceSlowSecondsPerKm
            details = workout.details
            structure = workout.structure
            statusRaw = workout.statusRaw
            manuallyOverridden = workout.manuallyOverridden
            matchedActivityUUID = workout.matchedActivityUUID
        }
    }
}
