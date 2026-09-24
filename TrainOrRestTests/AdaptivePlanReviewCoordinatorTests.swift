import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class AdaptivePlanReviewCoordinatorTests: XCTestCase {
    private let calendar = Calendar.current
    private var retainedContainer: ModelContainer?

    func testAutomaticMarkerPersistsBeforeProviderSuspends() throws {
        let (context, today) = try contextWithPlan()
        let client = AdaptiveReviewClient()
        let coordinator = coordinator(client: client, now: { today })
        let activityID = UUID()

        do {
            try coordinator.recordAutomaticRuns([.init(hkUUID: activityID, endDate: today)], in: context)
        } catch {
            XCTFail(error.localizedDescription)
            return
        }
        XCTAssertEqual(reviews(in: context).map(\.phase), [.queued])
        XCTAssertEqual(client.sendCount, 0)
    }

    func testAutomaticHKUUIDIsIdempotentAfterCoordinatorRecreation() throws {
        let (context, today) = try contextWithPlan()
        let activity = insertRun(in: context, date: today)
        try coordinator(now: { today }).recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)
        try coordinator(now: { today }).recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)

        XCTAssertEqual(reviews(in: context).count, 1)
    }

    func testInterruptedPreparingReviewDoesNotAutoRunAfterRelaunch() async throws {
        let (context, today) = try contextWithPlan()
        let review = manualReview(at: today)
        review.phaseRaw = AdaptivePlanReviewPhase.preparing.rawValue
        context.insert(review)
        try context.save()
        let client = AdaptiveReviewClient(responses: [.success(noChangeResponse())])

        await coordinator(client: client, now: { today }, automatic: { false }).syncDidSettle(in: context)

        XCTAssertEqual(review.phase, .failed)
        XCTAssertEqual(client.sendCount, 0)
    }

    func testFailedAutomaticReviewRunsAgainOnlyAfterManualRetry() async throws {
        let (context, today) = try contextWithPlan()
        try saveTestKey()
        defer { deleteTestKey() }
        let activity = insertRun(in: context, date: today)
        let client = AdaptiveReviewClient(responses: [.failure(TestError.failed), .success(noChangeResponse())])
        let coordinator = coordinator(client: client, now: { today })
        try coordinator.recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)

        await coordinator.syncDidSettle(in: context)
        let review = try XCTUnwrap(reviews(in: context).first)
        XCTAssertEqual(review.phase, .failed)
        await coordinator.syncDidSettle(in: context)
        XCTAssertEqual(client.sendCount, 1)

        await coordinator.handle(.retry, reviewID: review.id, in: context)
        XCTAssertEqual(review.phase, .noChange)
        XCTAssertEqual(review.latestAttemptKind, .manual)
        XCTAssertEqual(client.sendCount, 2)
    }

    func testNewAutomaticReviewSupersedesOlderWithoutUnioningActivityIDs() throws {
        let (context, today) = try contextWithPlan()
        let first = insertRun(in: context, date: today)
        let second = insertRun(in: context, date: today.addingTimeInterval(10))
        let coordinator = coordinator(now: { today })
        try coordinator.recordAutomaticRuns([.init(hkUUID: first.hkUUID, endDate: today)], in: context)
        try coordinator.recordAutomaticRuns([.init(hkUUID: second.hkUUID, endDate: today)], in: context)

        let records = reviews(in: context)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first(where: { $0.triggerActivityUUID == first.hkUUID })?.phase, .superseded)
        XCTAssertEqual(records.first(where: { $0.triggerActivityUUID == second.hkUUID })?.phase, .queued)
    }

    func testLateResponseFromSupersededAttemptIsDiscarded() async throws {
        let (context, today) = try contextWithPlan()
        try saveTestKey()
        defer { deleteTestKey() }
        let first = insertRun(in: context, date: today)
        let second = insertRun(in: context, date: today)
        let client = ControlledAdaptiveReviewClient()
        let coordinator = coordinator(client: client, now: { today })
        try coordinator.recordAutomaticRuns([.init(hkUUID: first.hkUUID, endDate: today)], in: context)

        let settle = Task { await coordinator.syncDidSettle(in: context) }
        _ = try await requestWithinFiveSeconds(from: client)
        try coordinator.recordAutomaticRuns([.init(hkUUID: second.hkUUID, endDate: today)], in: context)
        client.resumeNext(with: .success(noChangeResponse()))
        _ = try await requestWithinFiveSeconds(from: client)
        client.resumeNext(with: .success(noChangeResponse()))
        await settle.value

        XCTAssertEqual(reviews(in: context).first(where: { $0.triggerActivityUUID == first.hkUUID })?.phase, .superseded)
        XCTAssertEqual(reviews(in: context).first(where: { $0.triggerActivityUUID == second.hkUUID })?.phase, .noChange)
        XCTAssertEqual(client.sendCount, 2)
    }

    func testMissingKeyIsVisibleAndNoRequestIsSent() async throws {
        let (context, today) = try contextWithPlan()
        deleteTestKey()
        let client = AdaptiveReviewClient()
        let coordinator = coordinator(client: client, now: { today })

        await coordinator.beginManualReview(activityID: nil, in: context)

        XCTAssertEqual(reviews(in: context).first?.phase, .needsKey)
        XCTAssertEqual(client.sendCount, 0)
    }

    func testNoChangesResponsePersistsPlainNoChangeState() async throws {
        let (context, today) = try contextWithPlan()
        try saveTestKey()
        defer { deleteTestKey() }
        let client = AdaptiveReviewClient(responses: [.success(noChangeResponse(summary: "No adjustments."))])

        await coordinator(client: client, now: { today }).beginManualReview(activityID: nil, in: context)

        let review = try XCTUnwrap(reviews(in: context).first)
        XCTAssertEqual(review.phase, .noChange)
        XCTAssertEqual(review.summary, "No adjustments.")
        XCTAssertNil(review.proposalJSON)
    }

    func testSecondSettleEdgeDuringInFlightAttemptSendsNoSecondRequest() async throws {
        let (context, today) = try contextWithPlan()
        try saveTestKey()
        defer { deleteTestKey() }
        let activity = insertRun(in: context, date: today)
        let client = ControlledAdaptiveReviewClient()
        let coordinator = coordinator(client: client, now: { today })
        try coordinator.recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)

        let firstSettle = Task { await coordinator.syncDidSettle(in: context) }
        _ = try await requestWithinFiveSeconds(from: client)
        await coordinator.syncDidSettle(in: context)

        XCTAssertEqual(client.sendCount, 1)
        client.resumeNext(with: .success(noChangeResponse()))
        await firstSettle.value
    }

    func testSettleWhileSceneInactiveSendsNoRequest() async throws {
        let (context, today) = try contextWithPlan()
        let activity = insertRun(in: context, date: today)
        let client = AdaptiveReviewClient(responses: [.success(noChangeResponse())])
        let coordinator = coordinator(client: client, now: { today }, active: { false })
        try coordinator.recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)

        await coordinator.syncDidSettle(in: context)

        XCTAssertEqual(reviews(in: context).first?.phase, .queued)
        XCTAssertEqual(client.sendCount, 0)
    }

    func testHistoricalInsertsCreateNoAutomaticMarker() throws {
        let (context, today) = try contextWithPlan()
        let oldDate = calendar.date(byAdding: .day, value: -1, to: today)!
        let activity = insertRun(in: context, date: oldDate)

        try coordinator(now: { today }).recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: oldDate)], in: context)

        XCTAssertTrue(reviews(in: context).isEmpty)
    }

    func testSelectedOpenAIModelUsesOpenAIClient() async throws {
        let (context, today) = try contextWithPlan()
        UserDefaults.standard.set("gpt-5-nano", forKey: "coachModel")
        try KeychainStore.save("test-key", account: KeychainStore.openAIAPIKeyAccount)
        defer {
            UserDefaults.standard.removeObject(forKey: "coachModel")
            try? KeychainStore.delete(account: KeychainStore.openAIAPIKeyAccount)
        }
        let anthropic = AdaptiveReviewClient()
        let openAI = AdaptiveReviewClient(responses: [.success(noChangeResponse())])
        let coordinator = AdaptivePlanReviewCoordinator(anthropicClient: anthropic, openAIClient: openAI, now: { today }, isSceneActive: { true }, isAutomaticEnabled: { true })

        await coordinator.beginManualReview(activityID: nil, in: context)

        XCTAssertEqual(anthropic.sendCount, 0)
        XCTAssertEqual(openAI.sendCount, 1)
    }

    func testRelaunchedProposalAtSameRevisionAppliesWithoutStale() async throws {
        let (context, today) = try contextWithPlan()
        let review = proposalReview(in: context, at: today)
        context.insert(review)
        try context.save()

        await coordinator(now: { today }, automatic: { false }).syncDidSettle(in: context)

        XCTAssertEqual(review.phase, .proposal)
        XCTAssertNotNil(review.candidateID)
    }

    func testSupersedingRunQueuedDuringInFlightAttemptStartsAfterDiscard() async throws {
        let (context, today) = try contextWithPlan()
        let first = insertRun(in: context, date: today)
        let second = insertRun(in: context, date: today.addingTimeInterval(2))
        let coordinator = coordinator(now: { today })
        try coordinator.recordAutomaticRuns([.init(hkUUID: first.hkUUID, endDate: today)], in: context)
        try coordinator.recordAutomaticRuns([.init(hkUUID: second.hkUUID, endDate: today)], in: context)

        XCTAssertEqual(reviews(in: context).filter { $0.phase == .queued }.count, 1)
        XCTAssertEqual(reviews(in: context).filter { $0.phase == .superseded }.count, 1)
    }

    func testDrainWhileSceneInactiveLeavesSuccessorQueued() async throws {
        let (context, today) = try contextWithPlan()
        let activity = insertRun(in: context, date: today)
        let client = AdaptiveReviewClient(responses: [.success(noChangeResponse())])
        let coordinator = coordinator(client: client, now: { today }, active: { false })
        try coordinator.recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)

        await coordinator.syncDidSettle(in: context)

        XCTAssertEqual(reviews(in: context).first?.phase, .queued)
    }

    func testLaunchSyncSettleSendsWithoutScenePhaseChange() async throws {
        let (context, today) = try contextWithPlan()
        try saveTestKey()
        defer { deleteTestKey() }
        let activity = insertRun(in: context, date: today)
        let client = AdaptiveReviewClient(responses: [.success(noChangeResponse())])
        let coordinator = coordinator(client: client, now: { today })
        try coordinator.recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)

        await coordinator.syncDidSettle(in: context)

        XCTAssertEqual(reviews(in: context).first?.phase, .noChange)
    }

    func testDisablingAutomaticReviewBeforeDrainSendsNothing() async throws {
        let (context, today) = try contextWithPlan()
        try saveTestKey()
        defer { deleteTestKey() }
        var automatic = true
        let activity = insertRun(in: context, date: today)
        let client = AdaptiveReviewClient(responses: [.success(noChangeResponse())])
        let coordinator = coordinator(client: client, now: { today }, automatic: { automatic })
        try coordinator.recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)
        automatic = false

        await coordinator.syncDidSettle(in: context)

        XCTAssertEqual(client.sendCount, 0)
        XCTAssertEqual(reviews(in: context).first?.phase, .dismissed)
    }

    func testAutoMatchFailureStillRecordsAutomaticMarker() throws {
        let (context, today) = try contextWithPlan()
        let activity = insertRun(in: context, date: today)
        try coordinator(now: { today }).recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)

        XCTAssertEqual(reviews(in: context).first?.triggerActivityUUID, activity.hkUUID)
    }

    func testManualStartSupersedesQueuedAutomaticAndSettleSendsNothing() async throws {
        let (context, today) = try contextWithPlan()
        let activity = insertRun(in: context, date: today)
        let client = AdaptiveReviewClient()
        let coordinator = coordinator(client: client, now: { today })
        try coordinator.recordAutomaticRuns([.init(hkUUID: activity.hkUUID, endDate: today)], in: context)
        deleteTestKey()

        await coordinator.beginManualReview(activityID: nil, in: context)
        await coordinator.syncDidSettle(in: context)

        XCTAssertEqual(reviews(in: context).first(where: { $0.origin == .automatic })?.phase, .superseded)
        XCTAssertEqual(client.sendCount, 0)
    }

    func testEvidenceSetOmitsWorkoutsOlderThanSevenDays() async throws {
        let (context, today) = try contextWithPlan()
        try saveTestKey()
        defer { deleteTestKey() }
        insertRun(in: context, date: calendar.date(byAdding: .day, value: -8, to: today)!)
        let client = AdaptiveReviewClient(responses: [.success(noChangeResponse())])

        await coordinator(client: client, now: { today }).beginManualReview(activityID: nil, in: context)

        let request = try XCTUnwrap(client.requests.first)
        let body = try JSONEncoder().encode(request)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("-8"))
    }

    private func coordinator(
        client: ClaudeServicing,
        now: @escaping () -> Date,
        active: @escaping () -> Bool = { true },
        automatic: @escaping () -> Bool = { true }
    ) -> AdaptivePlanReviewCoordinator {
        AdaptivePlanReviewCoordinator(anthropicClient: client, openAIClient: client, now: now, isSceneActive: active, isAutomaticEnabled: automatic)
    }

    private func coordinator(
        now: @escaping () -> Date,
        active: @escaping () -> Bool = { true },
        automatic: @escaping () -> Bool = { true }
    ) -> AdaptivePlanReviewCoordinator {
        coordinator(client: AdaptiveReviewClient(), now: now, active: active, automatic: automatic)
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
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        retainedContainer = container
        let today = calendar.startOfDay(for: Date())
        let goal = GoalSpec(distance: .halfMarathon, targetTimeSeconds: 105 * 60, raceDate: calendar.date(byAdding: .day, value: 30, to: today)!, availableDays: Set(Weekday.allCases), longRunDay: .sunday)
        try PlanStore.replaceGoal(spec: goal, fitness: FitnessProfile(vdot: 44, weeklyVolumeKm: 30, volumeTrend: 0, longestRecentRunKm: 12), today: today, calendar: calendar, in: container.mainContext)
        return (container.mainContext, today)
    }

    @discardableResult
    private func insertRun(in context: ModelContext, date: Date) -> CompletedActivity {
        let activity = CompletedActivity(hkUUID: UUID(), date: date, distanceMeters: 5_000, durationSeconds: 1_800, avgHeartRate: 150, maxHeartRate: 165, avgPaceSecondsPerKm: 360, sourceName: "Test")
        context.insert(activity)
        try? context.save()
        return activity
    }

    private func reviews(in context: ModelContext) -> [AdaptivePlanReview] {
        (try? context.fetch(FetchDescriptor<AdaptivePlanReview>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    private func manualReview(at date: Date) -> AdaptivePlanReview {
        AdaptivePlanReview(triggerKey: "manual:\(UUID().uuidString)", origin: .manual, triggerActivityUUID: nil, window: NextSevenDayWindow(start: date, end: calendar.date(byAdding: .day, value: 7, to: date)!), createdAt: date)
    }

    private func proposalReview(in context: ModelContext, at date: Date) -> AdaptivePlanReview {
        let review = manualReview(at: date)
        let workout = (try? context.fetch(FetchDescriptor<PlannedWorkout>()))?.first { $0.date >= date && $0.date < calendar.date(byAdding: .day, value: 7, to: date)! }
        let proposal = PlanAdjustmentProposal(changes: [.init(date: CoachContextBuilder.day(workout?.date ?? date, calendar: calendar), action: .rest)])
        review.proposalJSON = String(data: try! JSONEncoder().encode(proposal), encoding: .utf8)
        review.phaseRaw = AdaptivePlanReviewPhase.proposal.rawValue
        return review
    }

    private func noChangeResponse(summary: String = "No changes needed.") -> ClaudeResponse {
        ClaudeResponse(content: [.toolUse(id: UUID().uuidString, name: AdaptiveReviewTool.name, input: .object([
            "outcome": .string("no_changes"),
            "summary": .string(summary),
            "changes": .array([])
        ]))], stopReason: "tool_use")
    }

    private func saveTestKey() throws {
        UserDefaults.standard.removeObject(forKey: "coachModel")
        try KeychainStore.save("test-key")
    }

    private func deleteTestKey() {
        try? KeychainStore.delete()
    }
}

@MainActor
private final class AdaptiveReviewClient: ClaudeServicing {
    var responses: [Result<ClaudeResponse, Error>]
    private(set) var requests: [ClaudeRequest] = []
    private(set) var sendCount = 0

    init(responses: [Result<ClaudeResponse, Error>] = []) {
        self.responses = responses
    }

    func send(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse {
        requests.append(request)
        sendCount += 1
        guard !responses.isEmpty else { throw TestError.failed }
        return try responses.removeFirst().get()
    }

    func stream(_ request: ClaudeRequest, apiKey: String) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
}

private enum TestError: LocalizedError {
    case failed
    var errorDescription: String? { "Test failure" }
}

@MainActor
private final class ControlledAdaptiveReviewClient: ClaudeServicing {
    private(set) var requests: [ClaudeRequest] = []
    private(set) var sendCount = 0
    private var pendingResponses: [CheckedContinuation<ClaudeResponse, Error>] = []
    private var requestWaiters: [CheckedContinuation<ClaudeRequest, Never>] = []

    func send(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse {
        requests.append(request)
        sendCount += 1
        if !requestWaiters.isEmpty {
            requestWaiters.removeFirst().resume(returning: request)
        }
        return try await withCheckedThrowingContinuation { pendingResponses.append($0) }
    }

    func stream(_ request: ClaudeRequest, apiKey: String) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func nextRequest() async -> ClaudeRequest {
        if let request = requests.last { return request }
        return await withCheckedContinuation { requestWaiters.append($0) }
    }

    func resumeNext(with result: Result<ClaudeResponse, Error>) {
        pendingResponses.removeFirst().resume(with: result)
    }
}

private func requestWithinFiveSeconds(from client: ControlledAdaptiveReviewClient) async throws -> ClaudeRequest {
    try await withThrowingTaskGroup(of: ClaudeRequest.self) { group in
        group.addTask { await client.nextRequest() }
        group.addTask {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw TestError.failed
        }
        guard let request = try await group.next() else { throw TestError.failed }
        group.cancelAll()
        return request
    }
}
