import SwiftData
import XCTest
@testable import TrainOrRest

/// What a question turn costs, measured in the units that actually drive wall clock:
/// provider rounds, prompt bytes spent on tool schemas, and the output token ceiling.
///
/// `.unspecified` is the routing a question used to get. It is still reachable through
/// `actionTypeOverride`, so both routings run against the same `CoachChatStore` and the
/// difference is observed, not asserted into existence.
@MainActor
final class CoachTurnCostTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let question = "Should I train or rest tomorrow?"

    func testQuestionRoutesToReadOnlyInsteadOfUnspecified() async throws {
        let bed = try makeBed()

        await bed.store.submitTestTurn(text: question, model: "claude-test", apiKey: "test-key", in: bed.context)

        let snapshot = try XCTUnwrap(try bed.context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(snapshot.actionType, .readOnly)
    }

    func testVietnameseQuestionRoutesToReadOnly() async throws {
        let bed = try makeBed()

        await bed.store.submitTestTurn(
            text: "Hôm nay tôi có nên chạy dài không",
            model: "claude-test",
            apiKey: "test-key",
            in: bed.context
        )

        let snapshot = try XCTUnwrap(try bed.context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(snapshot.actionType, .readOnly)
    }

    func testPlanEditStillRoutesToPlanMutation() async throws {
        let bed = try makeBed()

        await bed.store.submitTestTurn(
            text: "Update my calendar: shorten tomorrow's easy run. Apply it.",
            model: "claude-test",
            apiKey: "test-key",
            in: bed.context
        )

        let snapshot = try XCTUnwrap(try bed.context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(snapshot.actionType, .planMutation)
    }

    /// An edit phrased politely carries a question mark but still has to reach the plan
    /// tool. Routing it read-only would withhold the tool and turn the edit into prose.
    func testPoliteEditKeepsThePlanTool() async throws {
        for text in [
            "Can you move my long run to Sunday?",
            "Đổi buổi chạy dài sang chủ nhật được không?"
        ] {
            let bed = try makeBed()
            await bed.store.submitTestTurn(text: text, model: "claude-test", apiKey: "test-key", in: bed.context)

            let snapshot = try XCTUnwrap(try bed.context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
            XCTAssertNotEqual(snapshot.actionType, .readOnly, text)
            let tools = try XCTUnwrap(bed.client.requests.first).tools.map(\.name)
            XCTAssertTrue(tools.contains(CoachToolCatalog.planEditDraftName), "\(text) lost the plan tool")
        }
    }

    /// Hitting the output ceiling throws `CoachResponseError.truncated` and fails the turn,
    /// so the read-only ceiling has to clear the longest card this app has produced by a
    /// wide margin, not by a hair.
    func testReadOnlyCeilingClearsTheLongestMeasuredCard() {
        let longestMeasuredCardTokens = 1_000
        XCTAssertGreaterThanOrEqual(CoachChatConfig.readOnlyMaxOutputTokens, longestMeasuredCardTokens * 8)
        XCTAssertLessThan(CoachChatConfig.readOnlyMaxOutputTokens, CoachChatConfig.maxOutputTokens)
    }

    func testReadOnlyQuestionSpendsOneRoundWhereUnspecifiedBurnsTheBudget() async throws {
        let before = try await runQuestion(routing: .unspecified)
        let after = try await runQuestion(routing: nil)

        XCTAssertEqual(before.client.requests.count, CoachChatConfig.maxToolRounds)
        XCTAssertEqual(after.client.requests.count, 1)
    }

    func testReadOnlyQuestionStopsPayingForThePlanToolSchema() async throws {
        let before = try await runQuestion(routing: .unspecified)
        let after = try await runQuestion(routing: nil)

        let beforeTools = try XCTUnwrap(before.client.requests.first).tools
        let afterTools = try XCTUnwrap(after.client.requests.first).tools
        XCTAssertEqual(beforeTools.map(\.name), [CoachToolCatalog.coachResponseName, CoachToolCatalog.planEditDraftName])
        XCTAssertEqual(afterTools.map(\.name), [CoachToolCatalog.coachResponseName])
        XCTAssertLessThan(try schemaBytes(afterTools), try schemaBytes(beforeTools))
    }

    func testReadOnlyQuestionCapsOutputTokensAtTheCardCeiling() async throws {
        let before = try await runQuestion(routing: .unspecified)
        let after = try await runQuestion(routing: nil)

        XCTAssertEqual(try XCTUnwrap(before.client.requests.first).maxTokens, CoachChatConfig.maxOutputTokens)
        XCTAssertEqual(try XCTUnwrap(after.client.requests.first).maxTokens, CoachChatConfig.readOnlyMaxOutputTokens)
    }

    func testPlanMutationKeepsTheLargerOutputCeiling() {
        XCTAssertEqual(CoachChatConfig.maxOutputTokens(for: .planMutation), CoachChatConfig.maxOutputTokens)
        XCTAssertEqual(CoachChatConfig.maxOutputTokens(for: .unspecified), CoachChatConfig.maxOutputTokens)
        XCTAssertEqual(CoachChatConfig.maxOutputTokens(for: .readOnly), CoachChatConfig.readOnlyMaxOutputTokens)
    }

    /// Rounds times the output ceiling is the worst case number of tokens a turn can ask
    /// the provider to generate. It is the ceiling, not a measurement, but both ends come
    /// straight from the shipped configuration.
    func testWorstCaseOutputBudgetDropsTenFold() async throws {
        let before = try await runQuestion(routing: .unspecified)
        let after = try await runQuestion(routing: nil)

        let beforeBudget = before.client.requests.reduce(0) { $0 + $1.maxTokens }
        let afterBudget = after.client.requests.reduce(0) { $0 + $1.maxTokens }
        XCTAssertEqual(beforeBudget, CoachChatConfig.maxOutputTokens * CoachChatConfig.maxToolRounds)
        XCTAssertEqual(afterBudget, CoachChatConfig.readOnlyMaxOutputTokens)
        XCTAssertEqual(beforeBudget / afterBudget, 10)

        let report = """
        COACH_TURN_COST before rounds=\(before.client.requests.count) \
        schemaBytes=\(try schemaBytes(XCTUnwrap(before.client.requests.first).tools)) \
        maxTokens=\(try XCTUnwrap(before.client.requests.first).maxTokens) \
        outputBudget=\(beforeBudget)
        COACH_TURN_COST after rounds=\(after.client.requests.count) \
        schemaBytes=\(try schemaBytes(XCTUnwrap(after.client.requests.first).tools)) \
        maxTokens=\(try XCTUnwrap(after.client.requests.first).maxTokens) \
        outputBudget=\(afterBudget)
        """
        print(report)
    }

    func testProcessingStateCarriesTheRoundIndex() {
        let id = UUID()
        let state = CoachGenerationState.processing(messageId: id, stage: .buildingRecommendation, round: 3)

        guard case let .processing(messageId, stage, round) = state else {
            return XCTFail("expected a processing state")
        }
        XCTAssertEqual(messageId, id)
        XCTAssertEqual(stage, .buildingRecommendation)
        XCTAssertEqual(round, 3)
    }

    func testProcessingLabelHidesTheRoundOnTheFirstAttempt() {
        for language in [CoachLanguage.en, .ja, .vi] {
            XCTAssertEqual(
                language.processingLabel(for: .buildingRecommendation, round: 1),
                language.processingLabel(for: .buildingRecommendation)
            )
        }
    }

    func testProcessingLabelAnnouncesLaterRounds() {
        for language in [CoachLanguage.en, .ja, .vi] {
            let label = language.processingLabel(for: .buildingRecommendation, round: 4)
            XCTAssertTrue(label.hasPrefix(language.processingLabel(for: .buildingRecommendation)), label)
            XCTAssertTrue(label.contains("4"), label)
            XCTAssertTrue(label.contains("\(CoachChatConfig.maxToolRounds)"), label)
        }
    }

    /// Routing questions to `.readOnly` must not subject them to the review-card gate that
    /// the calendar and goal surfaces opt into. A composer question that gets a readable
    /// answer is done, and retrying it would spend the budget this change set out to save.
    func testComposerQuestionDoesNotDemandAReviewCard() async throws {
        let bed = try makeBed()
        bed.client.forcedResponse = CostModelCoachClient.conversationalCard

        await bed.store.submitTestTurn(text: question, model: "claude-test", apiKey: "test-key", in: bed.context)

        let snapshot = try XCTUnwrap(try bed.context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertFalse(snapshot.requiresStructuredCard)

        XCTAssertEqual(bed.client.requests.count, 1)
        let assistant = try XCTUnwrap(
            try bed.context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last { $0.role == .assistant }
        )
        XCTAssertEqual(assistant.interaction?.options.count, 2)
    }

    private func schemaBytes(_ tools: [ClaudeTool]) throws -> Int {
        try JSONEncoder().encode(tools).count
    }

    private struct Bed {
        let container: ModelContainer
        let context: ModelContext
        let client: CostModelCoachClient
        let store: CoachChatStore
    }

    private func runQuestion(routing: CoachRequestActionType?) async throws -> Bed {
        let bed = try makeBed()
        await bed.store.submitTestTurn(
            text: question,
            model: "claude-test",
            apiKey: "test-key",
            actionTypeOverride: routing,
            in: bed.context
        )
        return bed
    }

    private func makeBed() throws -> Bed {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = CostModelCoachClient()
        return Bed(
            container: container,
            context: context,
            client: client,
            store: CoachChatStore(client: client, calendar: calendar, now: { self.today })
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self,
            CoachRequestSnapshot.self, CoachMemoryItem.self, CoachPromptSuggestionRecord.self
        ])
        let configuration = ModelConfiguration("CoachTurnCostTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func seedMinimalTrainingData(in context: ModelContext) throws {
        context.insert(Goal(
            spec: GoalSpec(
                distance: .halfMarathon,
                targetTimeSeconds: 7_200,
                raceDate: PlanEngineTestSupport.date(2026, 4, 1),
                availableDays: [.monday, .wednesday, .friday, .sunday],
                longRunDay: .sunday
            ),
            createdAt: today
        ))
        context.insert(SyncState(domain: SyncState.workoutsDomain, lastSyncAt: today))
        try context.save()
    }
}

/// Answers the way the real provider answers under each tool configuration.
///
/// Offered the plan tool under `tool_choice = any`, the model reaches for it even when the
/// user asked a question. The draft has no concrete edit, the store rejects it, and the turn
/// spends another round. Offered only `coach_response`, it answers once.
@MainActor
private final class CostModelCoachClient: ClaudeServicing {
    private(set) var requests: [ClaudeRequest] = []
    var forcedResponse: ClaudeResponse?

    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        requests.append(request)
        return response(for: request)
    }

    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        requests.append(request)
        let response = self.response(for: request)
        return AsyncThrowingStream { continuation in
            Self.emit(response: response, into: continuation)
        }
    }

    private func response(for request: ClaudeRequest) -> ClaudeResponse {
        if let forcedResponse { return forcedResponse }
        let offersPlanTool = request.tools.contains { $0.name == CoachToolCatalog.planEditDraftName }
        return offersPlanTool ? Self.unusablePlanDraft : Self.answerCard
    }

    private static let answerCard = ClaudeResponse(
        content: [
            .toolUse(
                id: "toolu_card",
                name: CoachToolCatalog.coachResponseName,
                input: .object([
                    "content": .string(String(repeating: "Chạy nhẹ hôm nay rồi đánh giá lại vào sáng mai. ", count: 52)),
                    "title": .string("Train tomorrow"),
                    "summary": .string("Readiness is train, so keep the easy run and reassess in the morning.")
                ])
            )
        ],
        stopReason: "tool_use"
    )

    /// Content plus choices, no title and no summary. A composer question does not demand a
    /// review card, so this must render as written.
    static let conversationalCard = ClaudeResponse(
        content: [
            .toolUse(
                id: "toolu_options",
                name: CoachToolCatalog.coachResponseName,
                input: .object([
                    "content": .string("Tomorrow is an easy run. How do you want to handle it?"),
                    "interaction": .object([
                        "id": .string("next_step"),
                        "type": .string("single_choice"),
                        "options": .array([
                            .object([
                                "id": .string("keep_plan"),
                                "label": .string("Keep the plan"),
                                "value": .string("Keep tomorrow as planned.")
                            ]),
                            .object([
                                "id": .string("rest"),
                                "label": .string("Rest instead"),
                                "value": .string("Swap tomorrow for rest.")
                            ])
                        ]),
                        "allowOther": .bool(false),
                        "status": .string("pending")
                    ])
                ])
            )
        ],
        stopReason: "tool_use"
    )

    /// A well formed draft that targets a day with no planned workout, which is what the
    /// model produces when it is forced to call the plan tool to answer a question.
    private static let unusablePlanDraft = ClaudeResponse(
        content: [
            .toolUse(
                id: "toolu_draft",
                name: CoachToolCatalog.planEditDraftName,
                input: .object([
                    "changes": .array([
                        .object([
                            "date": .string("2026-01-06"),
                            "action": .string("downgrade")
                        ])
                    ])
                ])
            )
        ],
        stopReason: "tool_use"
    )

    private static func emit(
        response: ClaudeResponse,
        into continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) {
        continuation.yield(.messageStart)
        for (index, block) in response.content.enumerated() {
            switch block {
            case .text(let text):
                continuation.yield(.contentBlockStart(index: index, kind: .text))
                continuation.yield(.textDelta(index: index, text))
                continuation.yield(.contentBlockStop(index: index))
            case let .toolUse(id, name, input):
                continuation.yield(.contentBlockStart(index: index, kind: .toolUse(id: id, name: name)))
                if let data = try? JSONEncoder().encode(input),
                   let json = String(data: data, encoding: .utf8) {
                    continuation.yield(.inputJSONDelta(index: index, json))
                }
                continuation.yield(.contentBlockStop(index: index))
            case .image, .toolResult, .passthrough:
                break
            }
        }
        continuation.yield(.messageDelta(stopReason: response.stopReason))
        continuation.yield(.messageStop)
        continuation.finish()
    }
}
