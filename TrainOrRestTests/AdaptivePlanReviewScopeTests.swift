import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class AdaptivePlanReviewScopeTests: XCTestCase {
    private let calendar = Calendar.current
    private var retainedContainer: ModelContainer?

    func testMixedValidAndOutOfWindowActionsRejectsWholeProposal() throws {
        let (context, today) = try contextWithPlan()
        let source = try XCTUnwrap(planned(in: context, windowFrom: today).first)
        let original = PlanWorkoutReceiptSnapshot(workout: source)
        let outside = calendar.date(byAdding: .day, value: 8, to: today)!
        let proposal = PlanAdjustmentProposal(changes: [
            .init(date: day(source.date), action: .rest),
            .init(date: day(outside), action: .create, workout: easyWorkout())
        ])

        XCTAssertThrowsError(try prepare(proposal, in: context, today: today))
        XCTAssertEqual(PlanWorkoutReceiptSnapshot(workout: source), original)
        XCTAssertTrue((try context.fetch(FetchDescriptor<PlanEdit>())).isEmpty)
    }

    func testManuallyOverriddenPlannedWorkoutRemainsEligible() throws {
        let (context, today) = try contextWithPlan()
        let source = try XCTUnwrap(planned(in: context, windowFrom: today).first)
        source.manuallyOverridden = true
        try context.save()

        let candidate = try prepare(.init(changes: [.init(date: day(source.date), action: .rest)]), in: context, today: today)

        XCTAssertEqual(candidate.scope, adaptiveScope(from: today))
    }

    func testDoneSkippedRaceAndMoveSwapTargetsAreRejected() throws {
        let (context, today) = try contextWithPlan()
        let rows = planned(in: context, windowFrom: today)
        let source = try XCTUnwrap(rows.first)
        let target = try XCTUnwrap(rows.dropFirst().first)
        source.status = .done
        try context.save()
        XCTAssertThrowsError(try prepare(.init(changes: [.init(date: day(source.date), action: .rest)]), in: context, today: today))

        source.status = .skipped
        try context.save()
        XCTAssertThrowsError(try prepare(.init(changes: [.init(date: day(source.date), action: .rest)]), in: context, today: today))

        source.status = .planned
        source.kindRaw = WorkoutKind.race.rawValue
        try context.save()
        XCTAssertThrowsError(try prepare(.init(changes: [.init(date: day(source.date), action: .rest)]), in: context, today: today))

        source.kindRaw = WorkoutKind.easy.rawValue
        target.status = .done
        try context.save()
        XCTAssertThrowsError(try prepare(.init(changes: [.init(
            date: day(source.date),
            action: .move,
            detail: day(target.date)
        )]), in: context, today: today))
        XCTAssertThrowsError(try prepare(.init(changes: [.init(
            date: day(source.date),
            action: .swap,
            detail: day(target.date)
        )]), in: context, today: today))
    }

    func testApplyWithAcknowledgeLoadRiskWritesReceipt() throws {
        let (context, today) = try contextWithPlan()
        let source = try XCTUnwrap(planned(in: context, windowFrom: today).first)
        let candidate = try prepare(.init(changes: [.init(date: day(source.date), action: .rest)]), in: context, today: today)

        let result = try CoachPlanCandidateEngine.commit(candidate, in: context, today: today, calendar: calendar, language: .en, acknowledging: candidate.warnings)

        guard case let .applied(receipt) = result else { return XCTFail("Expected adaptive receipt") }
        XCTAssertEqual((try context.fetch(FetchDescriptor<PlanEdit>())).filter { $0.id == receipt.id }.count, 1)
    }

    func testStaleReviewCarriesAdaptiveScopeAndNeedsNewApply() throws {
        let (context, today) = try contextWithPlan()
        let source = try XCTUnwrap(planned(in: context, windowFrom: today).first)
        let candidate = try prepare(.init(changes: [.init(date: day(source.date), action: .rest)]), in: context, today: today)
        let plan = try XCTUnwrap(try PlanStore.activePlan(in: context))
        plan.generatedAt = today.addingTimeInterval(1)
        try context.save()

        let result = try CoachPlanCandidateEngine.commit(candidate, in: context, today: today, calendar: calendar, language: .en)

        guard case let .stale(fresh) = result else { return XCTFail("Expected stale candidate") }
        XCTAssertEqual(fresh.scope, adaptiveScope(from: today))
        XCTAssertTrue(fresh.changedSinceProposed)
        XCTAssertTrue((try context.fetch(FetchDescriptor<PlanEdit>())).isEmpty)

        let replacement = try CoachPlanCandidateEngine.commit(fresh, in: context, today: today, calendar: calendar, language: .en)
        guard case let .applied(receipt) = replacement else { return XCTFail("Expected replacement receipt") }
        XCTAssertEqual((try context.fetch(FetchDescriptor<PlanEdit>())).filter { $0.id == receipt.id }.count, 1)
    }

    func testRelaunchedStaleReviewRehydratesFreshDiffAndApplies() async throws {
        let (context, today) = try contextWithPlan()
        let source = try XCTUnwrap(planned(in: context, windowFrom: today).first)
        let proposal = PlanAdjustmentProposal(changes: [.init(date: day(source.date), action: .rest)])
        let review = AdaptivePlanReview(triggerKey: "manual:\(UUID())", origin: .manual, triggerActivityUUID: nil, window: window(from: today), createdAt: today)
        review.phaseRaw = AdaptivePlanReviewPhase.stale.rawValue
        review.proposalJSON = String(data: try JSONEncoder().encode(proposal), encoding: .utf8)
        context.insert(review)
        try context.save()

        let reloadedContext = ModelContext(try XCTUnwrap(retainedContainer))
        let coordinator = AdaptivePlanReviewCoordinator(
            anthropicClient: AdaptiveScopeClient(),
            openAIClient: AdaptiveScopeClient(),
            now: { today },
            isSceneActive: { true },
            isAutomaticEnabled: { false }
        )
        await coordinator.syncDidSettle(in: reloadedContext)

        let reloadedReview = try XCTUnwrap((try reloadedContext.fetch(FetchDescriptor<AdaptivePlanReview>())).first { $0.id == review.id })
        XCTAssertEqual(reloadedReview.phase, .stale)
        XCTAssertNotNil(reloadedReview.candidateID)
        await coordinator.handle(.apply(acknowledging: []), reviewID: reloadedReview.id, in: reloadedContext)
        XCTAssertEqual(reloadedReview.phase, .applied)
        XCTAssertEqual((try reloadedContext.fetch(FetchDescriptor<PlanEdit>())).count, 1)
    }

    private func prepare(_ proposal: PlanAdjustmentProposal, in context: ModelContext, today: Date) throws -> CoachPlanCandidate {
        try CoachPlanCandidateEngine.prepare(proposal: proposal, scope: adaptiveScope(from: today), in: context, today: today, calendar: calendar, language: .en)
    }

    private func adaptiveScope(from today: Date) -> PlanEditScope {
        .adaptiveNextWeek(window(from: today))
    }

    private func window(from today: Date) -> NextSevenDayWindow {
        let start = calendar.startOfDay(for: today)
        return NextSevenDayWindow(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }

    private func day(_ date: Date) -> String { CoachContextBuilder.day(date, calendar: calendar) }

    private func easyWorkout() -> PlanAdjustmentProposal.CreateWorkout {
        .init(kind: "easy", blocks: [.init(repeatCount: 1, steps: [.init(role: "work", targetType: "distance_km", targetValue: 4, paceZone: "easy")])])
    }

    private func contextWithPlan() throws -> (ModelContext, Date) {
        let schema = Schema([Goal.self, TrainingPlan.self, PlannedWorkout.self, CompletedActivity.self, PlanEdit.self, AdaptivePlanReview.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        retainedContainer = container
        let today = calendar.startOfDay(for: Date())
        let goal = GoalSpec(distance: .halfMarathon, targetTimeSeconds: 105 * 60, raceDate: calendar.date(byAdding: .day, value: 30, to: today)!, availableDays: Set(Weekday.allCases), longRunDay: .sunday)
        try PlanStore.replaceGoal(spec: goal, fitness: FitnessProfile(vdot: 44, weeklyVolumeKm: 30, volumeTrend: 0, longestRecentRunKm: 12), today: today, calendar: calendar, in: container.mainContext)
        return (container.mainContext, today)
    }

    private func planned(in context: ModelContext, windowFrom today: Date) -> [PlannedWorkout] {
        let end = calendar.date(byAdding: .day, value: 7, to: today)!
        return ((try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []).filter { $0.date >= today && $0.date < end }
    }
}

@MainActor
private final class AdaptiveScopeClient: ClaudeServicing {
    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse { throw ScopeError.unused }
    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> { AsyncThrowingStream { $0.finish() } }
}

private enum ScopeError: Error { case unused }
