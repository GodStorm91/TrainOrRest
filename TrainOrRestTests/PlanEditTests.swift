import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class PlanEditTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let occupiedDay = PlanEngineTestSupport.date(2026, 1, 7)

    func testLegacyReceiptStillRevertsAfterOptionalTransactionFieldsWereAdded() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = try XCTUnwrap(workout(on: occupiedDay, in: context))
        let original = PlanWorkoutReceiptSnapshot(workout: workout)
        let plan = try XCTUnwrap(workout.plan)
        let beforeTarget = plan.weekTargetVolumesKm[workout.weekIndex]
        let edit = PlanEdit(
            appliedAt: today,
            workout: workout,
            weekTargetVolumeKmBefore: beforeTarget,
            afterKindRaw: WorkoutKind.easy.rawValue,
            afterDistanceKm: 5,
            afterPaceFastSecondsPerKm: nil,
            afterPaceSlowSecondsPerKm: nil,
            afterDetails: "Easy run at E pace",
            afterStructure: [],
            afterStatusRaw: WorkoutStatus.planned.rawValue,
            afterManuallyOverridden: true,
            afterMatchedActivityUUID: nil,
            weekTargetVolumeKmAfter: beforeTarget - workout.distanceKm + 5
        )
        context.insert(edit)
        workout.kindRaw = WorkoutKind.easy.rawValue
        workout.distanceKm = 5
        workout.paceFastSecondsPerKm = nil
        workout.paceSlowSecondsPerKm = nil
        workout.details = "Easy run at E pace"
        workout.structure = []
        workout.status = .planned
        workout.manuallyOverridden = true
        workout.matchedActivityUUID = nil
        var targets = plan.weekTargetVolumesKm
        targets[workout.weekIndex] = edit.weekTargetVolumeKmAfter
        plan.weekTargetVolumesKm = targets
        try context.save()

        XCTAssertNil(edit.operationData)
        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)

        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: workout), original)
        XCTAssertEqual(plan.weekTargetVolumesKm[workout.weekIndex], beforeTarget, accuracy: 0.001)
        XCTAssertEqual(edit.revertedAt, today)
    }

    func testTransactionRevertRefusesToClobberLaterWorkoutChange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let edit = try applyCandidate(in: context)
        let changed = try XCTUnwrap(workout(on: occupiedDay, in: context))
        changed.details = "Changed after coach edit"
        try context.save()

        XCTAssertThrowsError(
            try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)
        ) { error in
            XCTAssertEqual(error.localizedDescription, PlanEditStore.changedAfterEditMessage)
        }
        XCTAssertNil(edit.revertedAt)
    }

    func testTransactionRevertAfterSevenDaysIsRefused() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let edit = try applyCandidate(in: context)
        let tooLate = try XCTUnwrap(calendar.date(byAdding: .day, value: 8, to: today))

        XCTAssertThrowsError(
            try PlanEditStore.revert(edit.id, in: context, today: tooLate, calendar: calendar)
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Coach edits can only be reverted for 7 days.")
        }
        XCTAssertNil(edit.revertedAt)
    }

    func testTransactionCannotBeRevertedTwice() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let edit = try applyCandidate(in: context)
        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)

        XCTAssertThrowsError(
            try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)
        ) { error in
            XCTAssertEqual(error.localizedDescription, "That coach edit was already reverted.")
        }
    }

    private func applyCandidate(in context: ModelContext) throws -> PlanEdit {
        let candidate = try CoachPlanCandidateEngine.prepare(
            proposal: replacementProposal(),
            scope: .standard,
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        )
        let result = try CoachPlanCandidateEngine.commit(
            candidate,
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        )
        guard case .applied = result else {
            throw XCTSkip("Candidate unexpectedly became stale")
        }
        return try XCTUnwrap(context.fetch(FetchDescriptor<PlanEdit>()).first)
    }

    private func replacementProposal() -> PlanAdjustmentProposal {
        PlanAdjustmentProposal(changes: [.init(
            date: CoachContextBuilder.day(occupiedDay, calendar: calendar),
            action: .replace,
            detail: nil,
            workout: .init(
                kind: "easy",
                blocks: [.init(repeatCount: 1, steps: [.init(
                    role: "work", targetType: "distance_km", targetValue: 5, paceZone: "easy"
                )])]
            )
        )])
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self, Goal.self,
            TrainingPlan.self, PlannedWorkout.self, DailyReadiness.self, DailyCheckIn.self,
            RuleOverride.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self,
            CoachRequestSnapshot.self, PlanEdit.self, AdaptivePlanReview.self
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
        try PlanStore.replaceGoal(
            spec: goal,
            fitness: FitnessProfile(vdot: 44, weeklyVolumeKm: 30, volumeTrend: 0, longestRecentRunKm: 12),
            today: today,
            calendar: calendar,
            in: container.mainContext
        )
        return container
    }

    private func workout(on date: Date, in context: ModelContext) throws -> PlannedWorkout? {
        try context.fetch(FetchDescriptor<PlannedWorkout>()).first {
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }
}
