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

    func testCoachContextTreatsRaceTargetAsWorkoutContext() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)

        let text = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertTrue(text.contains("target time can be context for a training request"))
        XCTAssertTrue(text.contains("not a goal change or race workout"))
        XCTAssertTrue(text.contains("if no day is stated, ask which day to schedule it"))
    }

    func testCoachContextIncludesPersonalSettingsFromUserDefaults() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        UserDefaults.standard.set("37", forKey: PersonalCoachSettings.ageKey)
        UserDefaults.standard.set("170", forKey: PersonalCoachSettings.heightCmKey)
        UserDefaults.standard.set("62.5", forKey: PersonalCoachSettings.weightKgKey)
        UserDefaults.standard.set("Diet: vegetarian\nInjury: recovering from flu", forKey: PersonalCoachSettings.storageKey)
        defer {
            UserDefaults.standard.removeObject(forKey: PersonalCoachSettings.ageKey)
            UserDefaults.standard.removeObject(forKey: PersonalCoachSettings.heightCmKey)
            UserDefaults.standard.removeObject(forKey: PersonalCoachSettings.weightKgKey)
            UserDefaults.standard.removeObject(forKey: PersonalCoachSettings.storageKey)
        }

        let text = try CoachContextBuilder.build(in: context, today: today, calendar: calendar)

        XCTAssertTrue(text.contains("Personal coach settings."))
        XCTAssertTrue(text.contains("Age: 37 years"))
        XCTAssertTrue(text.contains("Height: 170 cm"))
        XCTAssertTrue(text.contains("Weight: 62.5 kg"))
        XCTAssertTrue(text.contains("Diet: vegetarian"))
        XCTAssertTrue(text.contains("recovering from flu"))
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

        _ = try CoachTools.apply(
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

    func testPlanAdjustmentCanRestOneDayAndCreateWorkoutOnFreeDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let freeDay = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        let beforeToday = try plannedWorkouts(on: today, in: context)
        XCTAssertFalse(beforeToday.isEmpty)
        XCTAssertTrue(try plannedWorkouts(on: freeDay, in: context).isEmpty)

        let workout = PlanAdjustmentProposal.CreateWorkout(
            kind: "easy",
            blocks: [.init(repeatCount: 1, steps: [.init(
                role: "work",
                targetType: "distance_km",
                targetValue: 8,
                paceZone: "easy"
            )])]
        )

        let result = try CoachTools.apply(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: CoachContextBuilder.day(today, calendar: calendar), action: .rest),
                .init(date: CoachContextBuilder.day(freeDay, calendar: calendar), action: .create, workout: workout)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(result.summary.contains("Rested 2026-01-05"))
        XCTAssertTrue(result.summary.contains("Created easy on 2026-01-10"))
        XCTAssertTrue(try plannedWorkouts(on: today, in: context).isEmpty)
        let created = try XCTUnwrap(try plannedWorkouts(on: freeDay, in: context).first)
        XCTAssertEqual(created.kind, .easy)
        XCTAssertEqual(created.distanceKm, 8, accuracy: 0.001)
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
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Make Wednesday easier.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertNotNil(coordinator.pendingProposal)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertFalse(try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first).manuallyOverridden)

        let pending = try XCTUnwrap(coordinator.pendingProposal)
        coordinator.confirmProposal(pending.id)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .assistant])
        XCTAssertEqual(messages.last?.appliedAdjustment, "Downgraded 2026-01-07 to easy")
        XCTAssertTrue(try XCTUnwrap(try plannedWorkouts(on: qualityDay, in: context).first).manuallyOverridden)
    }

    func testChatStoreRejectsICSCalendarDetourAndStagesPlanToolInstead() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [.text("BEGIN:VCALENDAR\nDTSTART:20260107T080000\nSUMMARY:Easy run\nEND:VCALENDAR")], stopReason: "end_turn"),
            ClaudeResponse(content: [
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object([
                    "changes": .array([
                        .object([
                            "date": .string(CoachContextBuilder.day(qualityDay, calendar: calendar)),
                            "action": .string("downgrade")
                        ])
                    ])
                ]))
            ], stopReason: "tool_use")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Update my plan this week.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertNotNil(coordinator.pendingProposal)
        XCTAssertEqual(client.requests.count, 2)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("VCALENDAR"))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(messages.last?.text.contains("I prepared this calendar update") == true)
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

    /// End-to-end: user asks, model calls the tool, the app builds and saves a
    /// canonical workout, and the second round summarizes it.
    func testChatStoreCreatesStructuredWorkoutEndToEnd() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0) // left empty by the generator
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .passthrough(.object(["type": .string("thinking"), "thinking": .string("free day"), "signature": .string("sig")])),
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("create"),
                        "workout": .object([
                            "kind": .string("easy"),
                            "blocks": .array([.object([
                                "repeat_count": .number(1),
                                "steps": .array([.object([
                                    "role": .string("work"),
                                    "target_type": .string("distance_km"),
                                    "target_value": .number(5),
                                    "pace_zone": .string("easy")
                                ])])
                            ])])
                        ])
                    ])])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [.text("Added a 5 km easy run on Saturday.")], stopReason: "end_turn")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Add an easy run on Saturday.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let pending = try XCTUnwrap(coordinator.pendingProposal)
        XCTAssertTrue(pending.summary.contains("Created easy on 2026-01-10"))
        XCTAssertEqual(client.requests.count, 1)

        coordinator.confirmProposal(pending.id)

        let created = try XCTUnwrap(try plannedWorkouts(on: saturday, in: context).first)
        XCTAssertEqual(created.kind, .easy)
        XCTAssertEqual(created.distanceKm, 5, accuracy: 0.001)
        XCTAssertTrue(created.manuallyOverridden)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.last?.appliedAdjustment, "Created easy on 2026-01-10")
    }

    func testChatStoreRejectsUnapplyablePlanCardBeforeUserCanConfirm() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0) // free day
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let workout = PlanAdjustmentProposal.CreateWorkout(
            kind: "easy",
            blocks: [.init(repeatCount: 1, steps: [.init(
                role: "work",
                targetType: "distance_km",
                targetValue: 5,
                paceZone: "easy"
            )])]
        )
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_bad", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("rest")
                    ])])
                ]))
            ], stopReason: "tool_use"),
            ClaudeResponse(content: [
                .toolUse(id: "toolu_good", name: CoachTools.toolName, input: .object([
                    "changes": .array([.object([
                        "date": .string(CoachContextBuilder.day(saturday, calendar: calendar)),
                        "action": .string("create"),
                        "workout": .object([
                            "kind": .string(workout.kind),
                            "blocks": .array([.object([
                                "repeat_count": .number(1),
                                "steps": .array([.object([
                                    "role": .string("work"),
                                    "target_type": .string("distance_km"),
                                    "target_value": .number(5),
                                    "pace_zone": .string("easy")
                                ])])
                            ])])
                        ])
                    ])])
                ]))
            ], stopReason: "tool_use")
        ])
        let coordinator = WorkoutReplacementCoordinator(container: container, calendar: calendar, now: { self.today })
        let store = CoachChatStore(
            client: client,
            calendar: calendar,
            now: { self.today },
            replacementCoordinator: coordinator
        )

        await store.send(text: "Make Saturday a run day.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertEqual(client.requests.count, 2)
        let pending = try XCTUnwrap(coordinator.pendingProposal)
        XCTAssertEqual(pending.summary, "Created easy on 2026-01-10")
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertFalse(messages.map(\.text).joined(separator: "\n").contains("No workout on 2026-01-10"))
    }

    func testValidateForConfirmationDoesNotPersistAndRejectsMissingWorkoutEdit() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedEveryDayPlan(in: context)
        let saturday = PlanEngineTestSupport.date(2026, 1, 10, hour: 0)
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)

        XCTAssertThrowsError(try CoachTools.validateForConfirmation(
            proposal: PlanAdjustmentProposal(changes: [
                .init(date: CoachContextBuilder.day(saturday, calendar: calendar), action: .rest)
            ]),
            in: context,
            today: today,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error.localizedDescription, "No workout on 2026-01-10.")
        }
        XCTAssertNil(try plannedWorkouts(on: saturday, in: context).first)
    }

    func testTransientConnectionFailureIsNotPersistedAsAssistantMessage() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let client = MockClaudeClient(error: ClaudeClientError.connectionLost)
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Create a long run tomorrow.", model: "claude-test", apiKey: "test-key", in: context)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(messages.map(\.role), [.user])
        XCTAssertEqual(store.lastError, ClaudeClientError.connectionLost.errorDescription)
    }

    /// A truncated turn may carry a half-written tool input: never execute it.
    func testChatStoreRefusesToApplyTruncatedToolCall() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedTrainingData(in: context)
        let before = try context.fetch(FetchDescriptor<PlannedWorkout>()).count
        let client = MockClaudeClient(responses: [
            ClaudeResponse(content: [
                .toolUse(id: "toolu_1", name: CoachTools.toolName, input: .object(["changes": .array([])]))
            ], stopReason: "max_tokens")
        ])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Rebuild my week.", model: "claude-test", apiKey: "test-key", in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannedWorkout>()).count, before)
        XCTAssertEqual(client.requests.count, 1, "a truncated turn must not start another round")
        XCTAssertNotNil(store.lastError)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self
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

    /// Every weekday available, which leaves the generator a genuinely free day
    /// for the coach to create on.
    private func seedEveryDayPlan(in context: ModelContext) throws {
        let goal = GoalSpec(
            distance: .halfMarathon,
            targetTimeSeconds: 105 * 60,
            raceDate: PlanEngineTestSupport.date(2026, 4, 19),
            availableDays: Set(Weekday.allCases),
            longRunDay: .sunday
        )
        let fitness = FitnessProfile(vdot: 48, weeklyVolumeKm: 40, volumeTrend: 0, longestRecentRunKm: 16)
        try PlanStore.replaceGoal(spec: goal, fitness: fitness, today: today, calendar: calendar, in: context)
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
    private let error: Error?
    private(set) var requests: [ClaudeRequest] = []

    init(responses: [ClaudeResponse] = [], error: Error? = nil) {
        self.responses = responses
        self.error = error
    }

    func send(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse {
        requests.append(request)
        if let error { throw error }
        return responses.removeFirst()
    }
}
