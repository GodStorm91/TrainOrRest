import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class AdaptivePlanReviewReceiptTests: XCTestCase {
    private let calendar = Calendar.current
    private var retainedContainers: [ModelContainer] = []

    func testApplyWritesOneReceiptAndRevertUsesExactStateWithinSevenDays() throws {
        let (context, today) = try contextWithPlan()
        let (edit, source) = try applyRest(in: context, today: today)
        let review = review(for: edit, at: today)
        context.insert(review)
        try context.save()

        XCTAssertEqual((try context.fetch(FetchDescriptor<PlanEdit>())).count, 1)
        XCTAssertEqual(review.planEditID, edit.id)
        XCTAssertNil((try context.fetch(FetchDescriptor<PlannedWorkout>())).first { $0.uuid == source.uuid })

        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)

        XCTAssertEqual((try context.fetch(FetchDescriptor<PlannedWorkout>())).first { $0.uuid == source.uuid }?.status, .planned)
        XCTAssertEqual(edit.revertedAt, today)
    }

    func testRevertRefusesLaterMutationOrDayEight() throws {
        let (context, today) = try contextWithPlan()
        let (edit, source) = try applyDowngrade(in: context, today: today)
        source.details = "Changed after review"
        try context.save()
        XCTAssertThrowsError(try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar))

        let (freshContext, freshToday) = try contextWithPlan()
        let (freshEdit, _) = try applyRest(in: freshContext, today: freshToday)
        let dayEight = calendar.date(byAdding: .day, value: 8, to: freshToday)!
        XCTAssertThrowsError(try PlanEditStore.revert(freshEdit.id, in: freshContext, today: dayEight, calendar: calendar))
    }

    func testApplyAfterMidnightRejectsYesterdayWithoutWrite() throws {
        let (context, today) = try contextWithPlan()
        let source = try XCTUnwrap(nextWeekRows(in: context, today: today).first)
        let original = PlanWorkoutReceiptSnapshot(workout: source)
        let candidate = try candidate(for: source, in: context, today: today)
        let afterMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: source.date))!

        XCTAssertThrowsError(try CoachPlanCandidateEngine.commit(
            candidate,
            in: context,
            today: afterMidnight,
            calendar: calendar,
            language: .en
        ))

        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: source), original)
        XCTAssertTrue((try context.fetch(FetchDescriptor<PlanEdit>())).isEmpty)
    }

    func testApplyFailureRollsBackReviewPhase() async throws {
        let (context, today) = try contextWithPlan()
        let source = try XCTUnwrap(nextWeekRows(in: context, today: today).first)
        let original = PlanWorkoutReceiptSnapshot(workout: source)
        let proposal = PlanAdjustmentProposal(changes: [.init(date: day(source.date), action: .rest)])
        let review = AdaptivePlanReview(triggerKey: "manual:\(UUID())", origin: .manual, triggerActivityUUID: nil, window: window(today), createdAt: today)
        review.phaseRaw = AdaptivePlanReviewPhase.proposal.rawValue
        review.proposalJSON = String(decoding: try JSONEncoder().encode(proposal), as: UTF8.self)
        context.insert(review)
        try context.save()

        let client = ReceiptClient()
        let coordinator = AdaptivePlanReviewCoordinator(anthropicClient: client, openAIClient: client, now: { today }, isSceneActive: { true }, isAutomaticEnabled: { false })
        XCTAssertNotNil(coordinator.candidateForPresentation(reviewID: review.id, in: context))
        coordinator.beforeApplySaveForTesting = { _ in throw ReceiptError.rollback }

        await coordinator.handle(.apply(acknowledging: []), reviewID: review.id, in: context)

        XCTAssertEqual(review.phase, .proposal)
        XCTAssertNil(review.planEditID)
        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: source), original)
        XCTAssertTrue((try context.fetch(FetchDescriptor<PlanEdit>())).isEmpty)
    }

    func testBannerUndoMarksReviewReverted() throws {
        let (context, today) = try contextWithPlan()
        let (edit, _) = try applyRest(in: context, today: today)
        let review = review(for: edit, at: today)
        context.insert(review)
        try context.save()

        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)
        AdaptivePlanReviewCoordinator(anthropicClient: ReceiptClient(), openAIClient: ReceiptClient(), now: { today }, isSceneActive: { true }, isAutomaticEnabled: { false }).planDidChange(in: context)

        XCTAssertEqual(review.phase, .reverted)
    }

    func testNeedsKeyReviewStartsManuallyAfterKeyIsAdded() async throws {
        let (context, today) = try contextWithPlan()
        try? KeychainStore.delete()
        UserDefaults.standard.set(CoachConnection.anthropicKey.rawValue, forKey: CoachConnection.storageKey)
        defer {
            try? KeychainStore.delete()
            UserDefaults.standard.removeObject(forKey: CoachConnection.storageKey)
        }
        let client = ReceiptClient(response: noChangeResponse())
        let coordinator = AdaptivePlanReviewCoordinator(anthropicClient: client, openAIClient: client, now: { today }, isSceneActive: { true }, isAutomaticEnabled: { true })

        await coordinator.beginManualReview(activityID: nil, in: context)

        let review = try XCTUnwrap((try context.fetch(FetchDescriptor<AdaptivePlanReview>())).first)
        XCTAssertEqual(review.phase, .needsKey)
        XCTAssertEqual(client.sendCount, 0)
        try KeychainStore.save("test-key")
        XCTAssertEqual(client.sendCount, 0)

        await coordinator.handle(.retry, reviewID: review.id, in: context)

        XCTAssertEqual(client.sendCount, 1)
        XCTAssertEqual(review.phase, .noChange)
    }

    func testManualStartAvailableAfterAppliedAndReverted() async throws {
        let (context, today) = try contextWithPlan()
        let (edit, _) = try applyRest(in: context, today: today)
        let review = review(for: edit, at: today)
        context.insert(review)
        try context.save()
        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)

        XCTAssertEqual(review.phase, .reverted)
        XCTAssertEqual(
            AdaptivePlanReviewSlot.actions(for: review, selectedCoachIsConnected: true),
            [.manualReview]
        )

        try? KeychainStore.delete()
        UserDefaults.standard.set(CoachConnection.anthropicKey.rawValue, forKey: CoachConnection.storageKey)
        defer {
            try? KeychainStore.delete()
            UserDefaults.standard.removeObject(forKey: CoachConnection.storageKey)
        }
        try KeychainStore.save("test-key")
        let client = ReceiptClient(response: noChangeResponse())
        let coordinator = AdaptivePlanReviewCoordinator(
            anthropicClient: client,
            openAIClient: client,
            now: { today },
            isSceneActive: { true },
            isAutomaticEnabled: { true }
        )

        await coordinator.beginManualReview(activityID: nil, in: context)

        XCTAssertEqual(client.sendCount, 1)
    }

    func testBannerUndoPersistsRevertedWithoutCoordinatorRead() throws {
        let (context, today) = try contextWithPlan()
        let (edit, _) = try applyRest(in: context, today: today)
        let review = review(for: edit, at: today)
        context.insert(review)
        try context.save()

        try PlanEditStore.revert(edit.id, in: context, today: today, calendar: calendar)

        XCTAssertEqual(review.phase, .reverted)
    }

    func testRelaunchAfterMidnightFailsProposalWithoutCandidate() async throws {
        let (context, today) = try contextWithPlan()
        let source = try XCTUnwrap(nextWeekRows(in: context, today: today).first)
        let proposal = PlanAdjustmentProposal(changes: [.init(date: day(source.date), action: .rest)])
        let review = AdaptivePlanReview(
            triggerKey: "manual:\(UUID())",
            origin: .manual,
            triggerActivityUUID: nil,
            window: window(today),
            createdAt: today
        )
        review.phaseRaw = AdaptivePlanReviewPhase.proposal.rawValue
        review.proposalJSON = String(decoding: try JSONEncoder().encode(proposal), as: UTF8.self)
        context.insert(review)
        try context.save()

        let liveCoordinator = AdaptivePlanReviewCoordinator(
            anthropicClient: ReceiptClient(),
            openAIClient: ReceiptClient(),
            now: { today },
            isSceneActive: { true },
            isAutomaticEnabled: { false }
        )
        await liveCoordinator.syncDidSettle(in: context)
        XCTAssertEqual(review.phase, .proposal)
        XCTAssertNotNil(review.candidateID)

        let reloadedContext = ModelContext(try XCTUnwrap(retainedContainers.last))
        let reloadedReview = try XCTUnwrap((try reloadedContext.fetch(FetchDescriptor<AdaptivePlanReview>())).first { $0.id == review.id })
        await AdaptivePlanReviewCoordinator(
            anthropicClient: ReceiptClient(),
            openAIClient: ReceiptClient(),
            now: { self.calendar.date(byAdding: .day, value: 8, to: today)! },
            isSceneActive: { true },
            isAutomaticEnabled: { false }
        ).syncDidSettle(in: reloadedContext)

        XCTAssertEqual(reloadedReview.phase, .failed)
        XCTAssertNil(reloadedReview.candidateID)
    }

    func testScheduleLockedSourceAndSwapPartnerAreRejected() throws {
        let (context, today) = try contextWithPlan()
        let rows = nextWeekRows(in: context, today: today)
        let source = try XCTUnwrap(rows.first)
        let partner = try XCTUnwrap(rows.dropFirst().first)
        source.scheduleLock = true
        try context.save()

        XCTAssertThrowsError(try CoachPlanCandidateEngine.prepare(
            proposal: .init(changes: [.init(date: day(source.date), action: .replace)]),
            scope: .adaptiveNextWeek(window(today)),
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        ))
        XCTAssertThrowsError(try CoachPlanCandidateEngine.prepare(
            proposal: .init(changes: [.init(date: day(source.date), action: .move, detail: day(partner.date))]),
            scope: .adaptiveNextWeek(window(today)),
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        ))

        source.scheduleLock = false
        partner.scheduleLock = true
        try context.save()
        XCTAssertThrowsError(try CoachPlanCandidateEngine.prepare(
            proposal: .init(changes: [.init(date: day(source.date), action: .swap, detail: day(partner.date))]),
            scope: .adaptiveNextWeek(window(today)),
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        ))
    }

    private func applyRest(in context: ModelContext, today: Date) throws -> (PlanEdit, PlannedWorkout) {
        let source = try XCTUnwrap(nextWeekRows(in: context, today: today).first)
        let candidate = try candidate(for: source, in: context, today: today)
        let result = try CoachPlanCandidateEngine.commit(candidate, in: context, today: today, calendar: calendar, language: .en)
        guard case let .applied(receipt) = result else { throw ReceiptError.rollback }
        let edit = try XCTUnwrap((try context.fetch(FetchDescriptor<PlanEdit>())).first { $0.id == receipt.id })
        return (edit, source)
    }

    private func applyDowngrade(in context: ModelContext, today: Date) throws -> (PlanEdit, PlannedWorkout) {
        let source = try XCTUnwrap(nextWeekRows(in: context, today: today).first)
        let candidate = try CoachPlanCandidateEngine.prepare(
            proposal: .init(changes: [.init(date: day(source.date), action: .downgrade)]),
            scope: .adaptiveNextWeek(window(today)),
            in: context,
            today: today,
            calendar: calendar,
            language: .en
        )
        let result = try CoachPlanCandidateEngine.commit(candidate, in: context, today: today, calendar: calendar, language: .en)
        guard case let .applied(receipt) = result else { throw ReceiptError.rollback }
        let edit = try XCTUnwrap((try context.fetch(FetchDescriptor<PlanEdit>())).first { $0.id == receipt.id })
        return (edit, source)
    }

    private func candidate(for source: PlannedWorkout, in context: ModelContext, today: Date) throws -> CoachPlanCandidate {
        try CoachPlanCandidateEngine.prepare(proposal: .init(changes: [.init(date: day(source.date), action: .rest)]), scope: .adaptiveNextWeek(window(today)), in: context, today: today, calendar: calendar, language: .en)
    }

    private func review(for edit: PlanEdit, at date: Date) -> AdaptivePlanReview {
        let review = AdaptivePlanReview(triggerKey: "manual:\(UUID())", origin: .manual, triggerActivityUUID: nil, window: window(date), createdAt: date)
        review.phaseRaw = AdaptivePlanReviewPhase.applied.rawValue
        review.planEditID = edit.id
        return review
    }

    private func contextWithPlan() throws -> (ModelContext, Date) {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self, Goal.self,
            TrainingPlan.self, PlannedWorkout.self, DailyReadiness.self, DailyCheckIn.self,
            RuleOverride.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self,
            PlanEdit.self, AdaptivePlanReview.self, CoachRequestSnapshot.self,
            CoachMemoryItem.self, CoachPromptSuggestionRecord.self,
            GoogleCalendarConnection.self, GoogleCalendarEventLink.self,
            GoogleCalendarInboundChange.self, ScheduleChangeOperation.self,
            GoogleAvailabilityCalendar.self, DayAvailability.self,
            RunningShoe.self, ShoeMileageEntry.self, RunningShoePreferences.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        retainedContainers.append(container)
        let today = calendar.startOfDay(for: Date())
        let goal = GoalSpec(distance: .halfMarathon, targetTimeSeconds: 105 * 60, raceDate: calendar.date(byAdding: .day, value: 30, to: today)!, availableDays: Set(Weekday.allCases), longRunDay: .sunday)
        try PlanStore.replaceGoal(spec: goal, fitness: FitnessProfile(vdot: 44, weeklyVolumeKm: 30, volumeTrend: 0, longestRecentRunKm: 12), today: today, calendar: calendar, in: container.mainContext)
        return (container.mainContext, today)
    }

    private func nextWeekRows(in context: ModelContext, today: Date) -> [PlannedWorkout] {
        let end = calendar.date(byAdding: .day, value: 7, to: today)!
        return ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []).filter { $0.date >= today && $0.date < end }
    }

    private func window(_ today: Date) -> NextSevenDayWindow {
        NextSevenDayWindow(start: calendar.startOfDay(for: today), end: calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: today))!)
    }

    private func day(_ date: Date) -> String { CoachContextBuilder.day(date, calendar: calendar) }

    private func noChangeResponse() -> ClaudeResponse {
        ClaudeResponse(content: [.toolUse(id: UUID().uuidString, name: AdaptiveReviewTool.name, input: .object([
            "outcome": .string("no_changes"), "summary": .string("No changes needed."), "changes": .array([])
        ]))], stopReason: "tool_use")
    }
}

@MainActor
private final class ReceiptClient: ClaudeServicing {
    private var response: ClaudeResponse?
    private(set) var sendCount = 0

    init(response: ClaudeResponse? = nil) { self.response = response }

    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        sendCount += 1
        guard let response else { throw ReceiptError.rollback }
        return response
    }

    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private enum ReceiptError: Error { case rollback }
