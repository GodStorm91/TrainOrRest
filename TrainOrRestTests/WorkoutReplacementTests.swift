import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class WorkoutReplacementTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let occupiedDay = PlanEngineTestSupport.date(2026, 1, 7)

    func testPreparingReplacementIsReadOnlyAndCarriesExactDiff() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let before = try snapshot(in: context)
        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))

        let candidate = try replacementCandidate(in: context)

        XCTAssertEqual(try snapshot(in: context), before)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlanEdit>()).isEmpty)
        guard case .replacement(_, let shownBefore, let shownAfter, _, let volumeDelta) = candidate.presentation else {
            return XCTFail("Expected a replacement presentation")
        }
        XCTAssertEqual(shownBefore.kind, existing.kind)
        XCTAssertEqual(shownBefore.distanceKm, existing.distanceKm, accuracy: 0.001)
        XCTAssertEqual(volumeDelta, shownAfter.distanceKm - shownBefore.distanceKm, accuracy: 0.051)
        let operation = try XCTUnwrap(candidate.transaction.operations.first)
        XCTAssertEqual(operation.before?.uuid, existing.uuid)
        XCTAssertEqual(operation.after?.uuid, existing.uuid)
    }

    func testCommitAppliesStoredSnapshotAndWritesRevertibleReceipt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))
        existing.scheduleUpdatedAt = Date(timeIntervalSinceReferenceDate: 800_000_000.0004)
        try context.save()
        let original = PlanWorkoutReceiptSnapshot(workout: existing)
        let before = try snapshot(in: context)
        let candidate = try replacementCandidate(in: context)
        let expectedAfter = try XCTUnwrap(candidate.transaction.operations.first?.after)

        let result = try CoachPlanCandidateEngine.commit(
            candidate,
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        )
        guard case .applied(let receipt) = result else { return XCTFail("Expected commit") }

        let changed = try XCTUnwrap(workout(on: occupiedDay, in: context))
        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: changed), expectedAfter)
        let edit = try XCTUnwrap(context.fetch(FetchDescriptor<PlanEdit>()).first)
        XCTAssertEqual(edit.id, receipt.id)
        XCTAssertEqual(edit.summaryText, candidate.summary)
        XCTAssertEqual(edit.basePlanRevision, candidate.baseRevision)
        XCTAssertNotNil(edit.appliedPlanRevision)
        XCTAssertNotNil(edit.operationData)

        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)
        XCTAssertEqual(try snapshot(in: context), before)
        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: try XCTUnwrap(workout(on: occupiedDay, in: context))), original)
        XCTAssertEqual(edit.revertedAt, today)
    }

    func testCommitRestagesFreshCandidateWhenRevisionChanged() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let candidate = try replacementCandidate(in: context)
        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))
        existing.distanceKm += 1.5
        try context.save()
        let beforeCommit = try snapshot(in: context)

        let result = try CoachPlanCandidateEngine.commit(
            candidate,
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        )
        guard case .stale(let fresh) = result else { return XCTFail("Expected stale candidate") }

        XCTAssertTrue(fresh.changedSinceProposed)
        XCTAssertNotEqual(fresh.baseRevision, candidate.baseRevision)
        XCTAssertEqual(try snapshot(in: context), beforeCommit)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlanEdit>()).isEmpty)
    }

    func testStoreCancellationLeavesPlanUntouched() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let before = try snapshot(in: context)
        let candidate = try replacementCandidate(in: context)
        let store = CoachChatStore(calendar: calendar, now: { self.today })

        store.stagePlanCandidate(candidate)
        store.cancelPlanCandidate()
        guard case .ignored = store.confirmPlanCandidate(candidate.id, in: context) else {
            return XCTFail("Cancelled candidate must not commit")
        }

        XCTAssertEqual(try snapshot(in: context), before)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlanEdit>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ChatMessage>()).isEmpty)
    }

    func testStoreRestagesStaleCandidateThenCommitsOneReceipt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let candidate = try replacementCandidate(in: context)
        let store = CoachChatStore(calendar: calendar, now: { self.today })
        store.stagePlanCandidate(candidate)

        let existing = try XCTUnwrap(workout(on: occupiedDay, in: context))
        existing.distanceKm += 1.5
        try context.save()

        guard case .stale = store.confirmPlanCandidate(candidate.id, in: context) else {
            return XCTFail("Expected the store to restage a stale candidate")
        }
        let fresh = try XCTUnwrap(store.pendingPlanCandidate)
        XCTAssertTrue(fresh.changedSinceProposed)
        XCTAssertNotEqual(fresh.id, candidate.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlanEdit>()).isEmpty)

        guard case .applied(let receipt) = store.confirmPlanCandidate(fresh.id, in: context) else {
            return XCTFail("Expected the refreshed candidate to commit")
        }
        XCTAssertNil(store.pendingPlanCandidate)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlanEdit>()).map(\.id), [receipt.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).count, 1)
    }

    func testStoreReceiptRestoresPreCommitPlan() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let before = try snapshot(in: context)
        let candidate = try replacementCandidate(in: context)
        let store = CoachChatStore(calendar: calendar, now: { self.today })
        store.stagePlanCandidate(candidate)

        guard case .applied(let receipt) = store.confirmPlanCandidate(candidate.id, in: context) else {
            return XCTFail("Expected the staged candidate to commit")
        }
        try PlanEditStore.revert(receipt.id, in: context, today: today, calendar: calendar)

        XCTAssertEqual(try snapshot(in: context), before)
    }

    func testStoreKeepsCandidateWhenStaleProposalNoLongerApplies() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let candidate = try replacementCandidate(in: context)
        let store = CoachChatStore(calendar: calendar, now: { self.today })
        store.stagePlanCandidate(candidate)

        context.delete(try XCTUnwrap(workout(on: occupiedDay, in: context)))
        try context.save()

        guard case .failed = store.confirmPlanCandidate(candidate.id, in: context) else {
            return XCTFail("Expected stale revalidation to reject the obsolete proposal")
        }
        XCTAssertEqual(store.pendingPlanCandidate?.id, candidate.id)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlanEdit>()).isEmpty)
    }

    func testSuccessfulConfirmationClearsOlderTurnError() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let candidate = try replacementCandidate(in: context)
        let store = CoachChatStore(calendar: calendar, now: { self.today })
        store.stagePlanCandidate(candidate)
        store.lastError = "Previous send was blocked."

        guard case .applied = store.confirmPlanCandidate(candidate.id, in: context) else {
            return XCTFail("Expected confirmation to ignore an older turn error")
        }
        XCTAssertNil(store.lastError)
    }

    func testPendingCandidateBlocksInteractionBeforeResolution() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let candidate = try replacementCandidate(in: context)
        let store = CoachChatStore(calendar: calendar, now: { self.today })
        store.stagePlanCandidate(candidate)
        let interaction = CoachResponseInteraction(
            id: "next-step",
            type: .singleChoice,
            title: "Next step",
            options: [
                CoachChoiceOption(id: "keep", label: "Keep", description: nil, value: "Keep"),
                CoachChoiceOption(id: "change", label: "Change", description: nil, value: "Change")
            ],
            allowOther: false,
            status: .pending
        )
        let assistant = ChatMessage(
            role: .assistant,
            text: "Choose",
            date: today,
            status: .completed,
            interaction: interaction
        )
        context.insert(assistant)
        try context.save()

        let didSend = await store.submit(
            CoachTurnRequest(
                text: "Change",
                model: "claude-test",
                origin: .interaction(
                    messageID: assistant.turnID,
                    interactionID: interaction.id,
                    selectedOptionID: "change",
                    isCustomResponse: false
                )
            ),
            access: CoachAccess(connection: .anthropicKey, credential: .apiKey("test-key")),
            in: context
        )

        XCTAssertFalse(didSend)
        XCTAssertEqual(assistant.interaction?.status, .pending)
        XCTAssertEqual(store.pendingPlanCandidate?.id, candidate.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlanEdit>()).isEmpty)
    }

    private func replacementCandidate(in context: ModelContext) throws -> CoachPlanCandidate {
        let workout = PlanAdjustmentProposal.CreateWorkout(
            kind: "easy",
            blocks: [.init(repeatCount: 1, steps: [.init(
                role: "work", targetType: "distance_km", targetValue: 5, paceZone: "easy"
            )])]
        )
        return try CoachPlanCandidateEngine.prepare(
            proposal: PlanAdjustmentProposal(changes: [.init(
                date: CoachContextBuilder.day(occupiedDay, calendar: calendar),
                action: .replace,
                detail: nil,
                workout: workout
            )]),
            scope: .standard,
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self, Goal.self,
            TrainingPlan.self, PlannedWorkout.self, DailyReadiness.self, DailyCheckIn.self,
            PlanSnapshot.self, ChatThread.self, ChatMessage.self, CoachRequestSnapshot.self, PlanEdit.self,
            AdaptivePlanReview.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        for step in 0..<11 {
            container.mainContext.insert(CompletedActivity(
                hkUUID: UUID(),
                date: calendar.date(byAdding: .day, value: -(1 + step * 3), to: today)!,
                distanceMeters: 12_000,
                durationSeconds: 3_960,
                avgHeartRate: 145,
                maxHeartRate: 168,
                avgPaceSecondsPerKm: 330,
                sourceName: "Garmin"
            ))
        }
        try container.mainContext.save()
        let goal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 1, 25),
            availableDays: Set(Weekday.allCases),
            longRunDay: .sunday
        )
        let fitness = try PlanStore.currentFitness(in: container.mainContext, today: today, calendar: calendar)
            ?? FitnessProfile(vdot: 44, weeklyVolumeKm: 30, volumeTrend: 0, longestRecentRunKm: 12)
        try PlanStore.replaceGoal(
            spec: goal,
            fitness: fitness,
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

    private func snapshot(in context: ModelContext) throws -> [Row] {
        try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)])).map {
            Row(
                id: $0.uuid,
                kind: $0.kindRaw,
                distance: $0.distanceKm,
                details: $0.details,
                overridden: $0.manuallyOverridden,
                matched: $0.matchedActivityUUID
            )
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
