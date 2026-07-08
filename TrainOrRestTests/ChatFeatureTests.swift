import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class ChatFeatureTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let qualityDay = PlanEngineTestSupport.date(2026, 1, 7, hour: 0)

    func testCoachContextIncludesPlanReadinessAndFreshness() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        let text = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertLessThanOrEqual(text.count, CoachContextBuilder.maxCharacters)
        XCTAssertTrue(text.contains("Goal: Half Marathon"))
        XCTAssertTrue(text.contains("Plan next 14 days:"))
        XCTAssertTrue(text.contains("Last 14 days runs:"))
        XCTAssertTrue(text.contains("Readiness today: train"))
        XCTAssertTrue(text.contains("Data freshness:"))
    }

    func testToolDowngradeAppliesToPersistedPlan() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        let result = try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: CoachContextBuilder.day(qualityDay, calendar: calendar), action: .downgrade, detail: nil)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        let workouts = try plannedWorkouts(on: qualityDay, in: context)
        XCTAssertEqual(result.summary, "Downgraded 2026-01-07 to easy")
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.kind, .easy)
        XCTAssertEqual(workouts.first?.details, "Easy run at E pace")
        XCTAssertEqual(workouts.first?.manuallyOverridden, true)
        XCTAssertEqual(workouts.first?.structure.isEmpty, false)
    }

    func testToolDowngradeWithoutCurrentFitnessUsesUnpacedEasyStructure() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedGoalOnly(in: context)

        try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: CoachContextBuilder.day(qualityDay, calendar: calendar), action: .downgrade, detail: nil)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        let workout = try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first)
        XCTAssertEqual(workout.kind, .easy)
        XCTAssertNil(workout.paceBand)
        XCTAssertEqual(workout.structure.first?.steps.first?.role, .work)
        XCTAssertNil(workout.structure.first?.steps.first?.paceBand)
        XCTAssertEqual(workout.structure.first?.steps.first?.distanceKm, workout.distanceKm)
    }

    func testToolSwapPreservesWorkoutStructure() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let friday = PlanEngineTestSupport.date(2026, 1, 9, hour: 0)

        let result = try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(
                    date: CoachContextBuilder.day(qualityDay, calendar: calendar),
                    action: .swap,
                    detail: CoachContextBuilder.day(friday, calendar: calendar)
                )
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        let wednesdayWorkout = try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first)
        let fridayWorkout = try XCTUnwrap(try plannedWorkouts(on: friday, in: context).first)
        XCTAssertEqual(result.summary, "Swapped 2026-01-07 with 2026-01-09")
        XCTAssertEqual(wednesdayWorkout.kind, .easy)
        XCTAssertEqual(fridayWorkout.kind, .tempo)
        XCTAssertFalse(wednesdayWorkout.structure.isEmpty)
        XCTAssertFalse(fridayWorkout.structure.isEmpty)
    }

    func testToolRejectsPastWorkoutEdits() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        XCTAssertThrowsError(try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: "2026-01-04", action: .rest, detail: nil)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error.localizedDescription, "Cannot edit past workouts.")
        }
    }

    func testChatStoreRunsToolLoopAndPersistsAppliedAdjustment() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object([
                    "changes": .array([
                        .object([
                            "date": .string(CoachContextBuilder.day(qualityDay, calendar: calendar)),
                            "action": .string("downgrade")
                        ])
                    ])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [.text("I downgraded Wednesday to easy.")], stopReason: "end_turn")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Make Wednesday easier.", model: "claude-test", apiKey: "test-key", in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.last?.text, "I downgraded Wednesday to easy.")
        XCTAssertEqual(messages.last?.appliedAdjustment, "Downgraded 2026-01-07 to easy")
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertTrue(client.requests[1].messages.last?.content.contains {
            if case .toolResult(_, let content, false) = $0 {
                return content.contains("Applied: Downgraded 2026-01-07 to easy")
            }
            return false
        } ?? false)
    }

    func testChatStoreSendsAttachedContextAndImage() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let workout = try XCTUnwrap(try context.fetch(FetchDescriptor<PlannedWorkout>()).first)
        let image = CoachImageAttachment(data: Data([1, 2, 3]), mediaType: "image/jpeg", filename: "test.jpg")
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("Here is the context review.")], stopReason: "end_turn")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Review this workout.",
            model: "claude-test",
            attachments: [.health, .plannedWorkout(workout.uuid), .image(image)],
            apiKey: "test-key",
            in: context
        )

        let content = try XCTUnwrap(client.requests.first?.messages.last?.content)
        XCTAssertTrue(content.textContent.contains("Attached context:"))
        XCTAssertTrue(content.textContent.contains("Health snapshot:"))
        XCTAssertTrue(content.textContent.contains("Planned workout:"))
        XCTAssertTrue(content.contains {
            if case .image(let mediaType, let data) = $0 {
                return mediaType == "image/jpeg" && data == image.base64String
            }
            return false
        })
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, PlanSnapshot.self, ChatMessage.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func seedTrainingData(in context: ModelContext) throws {
        try seedGoalOnly(in: context)

        context.insert(CompletedActivity(
            hkUUID: UUID(),
            date: calendar.date(byAdding: .day, value: -1, to: today)!,
            distanceMeters: 10_000,
            durationSeconds: 3_300,
            avgHeartRate: 145,
            maxHeartRate: 168,
            avgPaceSecondsPerKm: 330,
            sourceName: "Garmin"
        ))
        context.insert(SyncState(domain: SyncState.workoutsDomain, lastSyncAt: today))
        context.insert(DailyReadiness(
            date: calendar.startOfDay(for: today),
            assessment: ReadinessAssessment(
                verdict: .train,
                reasons: [],
                baselineDayCount: 28,
                snapshot: .init(
                    hrvMean7: 52, hrvMean28: 51,
                    rhrMean7: 48, rhrMean28: 49,
                    sleepLastNight: 7.4, sleepMean14: 7.2,
                    acuteChronicRatio: 1.0
                )
            ),
            computedAt: today
        ))
        try context.save()
    }

    private func seedGoalOnly(in context: ModelContext) throws {
        let goal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 4, 19),
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday
        )
        let fitness = FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0, longestRecentRunKm: 16)
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)
    }

    private func plannedWorkouts(on date: Date, in context: ModelContext) throws -> [PlannedWorkout] {
        let day = calendar.startOfDay(for: date)
        return try context.fetch(FetchDescriptor<PlannedWorkout>()).filter {
            calendar.isDate($0.date, inSameDayAs: day)
        }
    }
}

@MainActor
private final class MockClaudeClient: ClaudeServicing {
    private var responses: [ClaudeResponse]
    private(set) var requests: [ClaudeRequest] = []

    init(responses: [ClaudeResponse]) {
        self.responses = responses
    }

    func send(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse {
        requests.append(request)
        return responses.removeFirst()
    }
}
