import SwiftData
import XCTest
@testable import TrainOrRest

@MainActor
final class CoachInteractionStateTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)

    func testTappingPromptSuggestionHidesImmediately() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = CoachChatStore(calendar: calendar, now: { self.today })
        let suggestion = promptSuggestion()

        store.setPromptSuggestionStatus(.consumed, for: suggestion, in: context)

        XCTAssertTrue(store.promptSuggestions(from: [suggestion], in: context).isEmpty)
    }

    func testConsumedSuggestionDoesNotReturnAfterReopeningConversation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = CoachChatStore(calendar: calendar, now: { self.today })
        let suggestion = promptSuggestion()

        store.setPromptSuggestionStatus(.consumed, for: suggestion, in: context)
        let restoredStore = CoachChatStore(calendar: calendar, now: { self.today })

        XCTAssertTrue(restoredStore.promptSuggestions(from: [suggestion], in: context).isEmpty)
    }

    func testSendFailureRestoresConsumedSuggestion() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(error: ClaudeClientError.connectionLost)
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })
        let suggestion = promptSuggestion()

        store.setPromptSuggestionStatus(.consumed, for: suggestion, in: context)
        let didSend = await store.send(text: suggestion.prompt, model: "claude-test", apiKey: "test-key", threadID: suggestion.conversationId, in: context)
        if !didSend {
            store.setPromptSuggestionStatus(.available, for: suggestion, in: context)
        }

        XCTAssertFalse(didSend)
        XCTAssertEqual(store.promptSuggestions(from: [suggestion], in: context).map(\.id), [suggestion.id])
    }

    func testSingleChoiceMetadataPersistsOnAssistantMessage() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.choiceResponse])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Review this run.", model: "claude-test", apiKey: "test-key", threadID: conversationID, in: context)

        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(assistant.text, "Buổi chạy nhìn chung phù hợp với tiến trình hiện tại. Bạn muốn tiếp tục thế nào?")
        XCTAssertEqual(assistant.interaction?.type, .singleChoice)
        XCTAssertEqual(assistant.interaction?.options.map(\.id), ["keep_plan", "adjust_plan"])
    }

    func testTextOnlyMessageDoesNotPersistChoiceCards() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.textOnly])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "What should I do?", model: "claude-test", apiKey: "test-key", threadID: conversationID, in: context)

        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertNil(assistant.interaction)
    }

    func testExpectedInteractionRendersWhenReadOnlyModelFallsBackToText() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.textOnly])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Propose a concrete adjustment. Do not modify the calendar directly.",
            model: "claude-test",
            apiKey: "test-key",
            threadID: conversationID,
            actionTypeOverride: .readOnly,
            expectedResponseInteraction: choiceInteraction(id: "goal_plan_adjustment_next_step"),
            in: context
        )

        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(assistant.text, "Run easy today.")
        XCTAssertEqual(assistant.interaction?.id, "goal_plan_adjustment_next_step")
        XCTAssertEqual(assistant.interaction?.status, .pending)
        XCTAssertEqual(assistant.interaction?.options.map(\.id), ["keep_plan", "adjust_plan"])
    }

    func testReadOnlyCoachRequestForcesStructuredResponseTool() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.choiceResponse])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(text: "Review this run.", model: "claude-test", apiKey: "test-key", threadID: conversationID, in: context)

        let request = try XCTUnwrap(client.requests.last)
        XCTAssertEqual(request.tools.map(\.name), [CoachToolCatalog.coachResponseName])
        XCTAssertEqual(request.toolChoice, .tool(name: CoachToolCatalog.coachResponseName))
    }

    func testActionTypeOverridePreventsRecommendationPromptFromBecomingPlanMutation() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.choiceResponse])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.send(
            text: "Propose a concrete adjustment. Do not modify the calendar directly.",
            model: "claude-test",
            apiKey: "test-key",
            threadID: conversationID,
            actionTypeOverride: .readOnly,
            expectedResponseInteraction: choiceInteraction(id: "goal_plan_adjustment_next_step"),
            in: context
        )

        let snapshot = try XCTUnwrap(try context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(snapshot.actionType, .readOnly)
        XCTAssertEqual(snapshot.expectedResponseInteraction?.id, "goal_plan_adjustment_next_step")
        XCTAssertEqual(client.requests.last?.tools.map(\.name), [CoachToolCatalog.coachResponseName])
        XCTAssertEqual(client.requests.last?.toolChoice, .tool(name: CoachToolCatalog.coachResponseName))
    }

    func testCalendarReviewPromptRequestUsesStableIdentity() {
        let prompt = "Propose a concrete adjustment. Do not modify the calendar directly."

        let first = CalendarReviewChatRequest(prompt: prompt)
        let second = CalendarReviewChatRequest(prompt: prompt)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.threadTitle, "Calendar schedule review")
    }

    func testStructuredContextIsNotRenderedInUserBubble() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.textOnly])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })
        let modelPrompt = """
        Review the remaining training plan.
        Goal ID: sub4
        Raw structured context: {"remainingWeeks":8,"target":"3:59:00"}
        """

        await store.send(
            text: modelPrompt,
            model: "claude-test",
            apiKey: "test-key",
            threadID: conversationID,
            actionTypeOverride: .readOnly,
            displayText: "Hãy đề xuất điều chỉnh kế hoạch 8 tuần còn lại.",
            contextSnapshotId: "goal-assessment-sub4",
            contextItems: [
                CoachContextItem(type: .raceGoal, label: "Mục tiêu Sub-4"),
                CoachContextItem(type: .remainingPlan, label: "8 tuần còn lại"),
                CoachContextItem(type: .trainingPlan, label: "Kế hoạch hiện tại")
            ],
            in: context
        )

        let user = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).first { $0.role == .user })
        let snapshot = try XCTUnwrap(try context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(user.text, "Hãy đề xuất điều chỉnh kế hoạch 8 tuần còn lại.")
        XCTAssertFalse(user.text.contains("Raw structured context"))
        XCTAssertEqual(user.contextItems.map(\.label), ["Mục tiêu Sub-4", "8 tuần còn lại", "Kế hoạch hiện tại"])
        XCTAssertEqual(snapshot.messageText, modelPrompt)
        XCTAssertEqual(snapshot.displayText, user.text)
        XCTAssertEqual(snapshot.contextSnapshotId, "goal-assessment-sub4")
        XCTAssertTrue(client.requests.last?.messages.last?.content.textContent.contains("Raw structured context") == true)
    }

    func testGenerationStateMovesThroughStreamingToCompleted() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.textOnly])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        let didSend = await store.send(
            text: "Review this run.",
            model: "claude-test",
            apiKey: "test-key",
            threadID: conversationID,
            in: context
        )

        XCTAssertTrue(didSend)
        guard case .completed(let messageId) = store.generationState else {
            return XCTFail("Expected completed generation state, got \(store.generationState)")
        }
        let assistant = try XCTUnwrap(try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.date)])).last)
        XCTAssertEqual(messageId, assistant.turnID)
        XCTAssertEqual(assistant.assistantStatus, .completed)
    }

    func testSelectingOptionSubmitsValueAndMetadata() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.textOnly])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })
        let assistant = assistantMessage(with: choiceInteraction())
        context.insert(assistant)
        try context.save()

        let option = choiceInteraction().options[1]
        _ = store.resolveInteraction(messageID: assistant.turnID, selectedOptionId: option.id, in: context)
        await store.send(
            text: option.value,
            model: "claude-test",
            apiKey: "test-key",
            threadID: conversationID,
            interactionId: "post_run_next_step",
            selectedOptionId: "adjust_plan",
            in: context
        )

        let snapshot = try XCTUnwrap(try context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertEqual(snapshot.messageText, "Hãy đề xuất cách điều chỉnh các buổi tập tiếp theo.")
        XCTAssertEqual(snapshot.interactionId, "post_run_next_step")
        XCTAssertEqual(snapshot.selectedOptionId, "adjust_plan")
        XCTAssertTrue(client.requests.last?.messages.last?.content.textContent.contains("optionId=adjust_plan") == true)
    }

    func testSelectingOptionCollapsesInteraction() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = CoachChatStore(calendar: calendar, now: { self.today })
        let assistant = assistantMessage(with: choiceInteraction())
        context.insert(assistant)
        try context.save()

        let resolved = store.resolveInteraction(messageID: assistant.turnID, selectedOptionId: "adjust_plan", in: context)

        XCTAssertEqual(resolved?.status, .resolved)
        XCTAssertEqual(assistant.interaction?.resolvedSummary(language: .vi), "Đã chọn: Xem đề xuất điều chỉnh")
    }

    func testOtherUsesPlaceholderAndCustomResolutionCopy() {
        var interaction = choiceInteraction()

        XCTAssertEqual(interaction.otherPlaceholder, "Bạn muốn Coach điều chỉnh như thế nào?")
        interaction.status = .resolved
        interaction.resolvedWithOther = true
        XCTAssertEqual(interaction.resolvedSummary(language: .vi), "Đã trả lời bằng yêu cầu khác")
    }

    func testSubmittingCustomResponseResolvesInteraction() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.textOnly])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })
        let assistant = assistantMessage(with: choiceInteraction())
        context.insert(assistant)
        try context.save()

        _ = store.resolveInteraction(messageID: assistant.turnID, selectedOptionId: nil, resolvedWithOther: true, in: context)
        await store.send(
            text: "Tăng nhẹ volume tuần sau.",
            model: "claude-test",
            apiKey: "test-key",
            threadID: conversationID,
            interactionId: "post_run_next_step",
            isCustomInteractionResponse: true,
            in: context
        )

        XCTAssertEqual(assistant.interaction?.status, .resolved)
        XCTAssertEqual(assistant.interaction?.resolvedWithOther, true)
        let snapshot = try XCTUnwrap(try context.fetch(FetchDescriptor<CoachRequestSnapshot>()).first)
        XCTAssertTrue(snapshot.isCustomInteractionResponse)
    }

    func testFailedOptionSubmissionRestoresPendingState() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(error: ClaudeClientError.connectionLost)
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })
        let original = choiceInteraction()
        let assistant = assistantMessage(with: original)
        context.insert(assistant)
        try context.save()

        _ = store.resolveInteraction(messageID: assistant.turnID, selectedOptionId: "adjust_plan", in: context)
        let didSend = await store.send(
            text: original.options[1].value,
            model: "claude-test",
            apiKey: "test-key",
            threadID: conversationID,
            interactionId: original.id,
            selectedOptionId: "adjust_plan",
            in: context
        )
        if !didSend {
            store.restoreInteraction(messageID: assistant.turnID, interaction: original, in: context)
        }

        XCTAssertFalse(didSend)
        XCTAssertEqual(assistant.interaction?.status, .pending)
        XCTAssertNil(assistant.interaction?.selectedOptionId)
    }

    func testRepeatedTapsDoNotGenerateDuplicateMessages() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = InteractionMockCoachClient(responses: [.delayedText, .textOnly])
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        async let first: Bool = store.send(text: "Review this run.", model: "claude-test", apiKey: "test-key", threadID: conversationID, in: context)
        async let second: Bool = store.send(text: "Review this run.", model: "claude-test", apiKey: "test-key", threadID: conversationID, in: context)
        _ = await (first, second)

        let userMessages = try context.fetch(FetchDescriptor<ChatMessage>()).filter { $0.role == .user }
        XCTAssertEqual(userMessages.count, 1)
    }

    func testNewestUnresolvedInteractionIsOnlyActionable() throws {
        let older = assistantMessage(with: choiceInteraction(id: "older"), date: today)
        let resolved = assistantMessage(with: {
            var interaction = choiceInteraction(id: "resolved")
            interaction.status = .resolved
            interaction.selectedOptionId = "keep_plan"
            return interaction
        }(), date: today.addingTimeInterval(1))
        let newest = assistantMessage(with: choiceInteraction(id: "newest"), date: today.addingTimeInterval(2))
        let messages = [older, resolved, newest]

        let actionable = messages.reversed().compactMap { message in
            message.interaction?.status == .pending ? message.interaction?.id : nil
        }.first

        XCTAssertEqual(actionable, "newest")
    }

    private var conversationID: UUID {
        UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    }

    private func promptSuggestion() -> CoachPromptSuggestion {
        CoachPromptSuggestion(
            id: "review-planned-target",
            workoutId: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            conversationId: conversationID,
            title: "Review this run against the planned target.",
            prompt: "Review this run against the planned target.",
            status: .available
        )
    }

    private func assistantMessage(with interaction: CoachResponseInteraction, date: Date? = nil) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            text: "Bạn muốn tiếp tục thế nào?",
            date: date ?? today,
            threadID: conversationID,
            status: .completed,
            interaction: interaction
        )
    }

    private func choiceInteraction(id: String = "post_run_next_step") -> CoachResponseInteraction {
        CoachResponseInteraction(
            id: id,
            type: .singleChoice,
            title: "Chọn bước tiếp theo",
            options: [
                CoachChoiceOption(
                    id: "keep_plan",
                    label: "Giữ nguyên kế hoạch",
                    description: "Không thay đổi các buổi tập sắp tới",
                    value: "Giữ nguyên kế hoạch hiện tại."
                ),
                CoachChoiceOption(
                    id: "adjust_plan",
                    label: "Xem đề xuất điều chỉnh",
                    description: "Coach đề xuất thay đổi dựa trên buổi chạy này",
                    value: "Hãy đề xuất cách điều chỉnh các buổi tập tiếp theo."
                )
            ],
            allowOther: true,
            otherLabel: "Yêu cầu khác…",
            otherPlaceholder: "Bạn muốn Coach điều chỉnh như thế nào?",
            status: .pending
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self,
            CoachRequestSnapshot.self, CoachMemoryItem.self, CoachPromptSuggestionRecord.self
        ])
        let configuration = ModelConfiguration("CoachInteractionStateTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
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

@MainActor
private final class InteractionMockCoachClient: ClaudeServicing {
    enum ResponseKind {
        case textOnly
        case choiceResponse
        case delayedText
    }

    private var responses: [ResponseKind]
    private let error: Error?
    private(set) var requests: [ClaudeRequest] = []

    init(responses: [ResponseKind] = [], error: Error? = nil) {
        self.responses = responses
        self.error = error
    }

    func send(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse {
        requests.append(request)
        if let error { throw error }
        return response(for: responses.isEmpty ? .textOnly : responses.removeFirst())
    }

    func stream(_ request: ClaudeRequest, apiKey: String) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        requests.append(request)
        if let error {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let kind = responses.isEmpty ? ResponseKind.textOnly : responses.removeFirst()
        if kind == .delayedText {
            return AsyncThrowingStream { continuation in
                Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    Self.emit(response: self.response(for: .textOnly), into: continuation)
                }
            }
        }
        return AsyncThrowingStream { continuation in
            Self.emit(response: self.response(for: kind), into: continuation)
        }
    }

    private func response(for kind: ResponseKind) -> ClaudeResponse {
        switch kind {
        case .textOnly, .delayedText:
            return ClaudeResponse(content: [.text("Run easy today.")], stopReason: "end_turn")
        case .choiceResponse:
            return ClaudeResponse(content: [
                .toolUse(
                    id: "toolu_response",
                    name: CoachToolCatalog.coachResponseName,
                    input: .object([
                        "content": .string("Buổi chạy nhìn chung phù hợp với tiến trình hiện tại. Bạn muốn tiếp tục thế nào?"),
                        "interaction": .object([
                            "id": .string("post_run_next_step"),
                            "type": .string("single_choice"),
                            "title": .string("Chọn bước tiếp theo"),
                            "options": .array([
                                .object([
                                    "id": .string("keep_plan"),
                                    "label": .string("Giữ nguyên kế hoạch"),
                                    "description": .string("Không thay đổi các buổi tập sắp tới"),
                                    "value": .string("Giữ nguyên kế hoạch hiện tại.")
                                ]),
                                .object([
                                    "id": .string("adjust_plan"),
                                    "label": .string("Xem đề xuất điều chỉnh"),
                                    "description": .string("Coach đề xuất thay đổi dựa trên buổi chạy này"),
                                    "value": .string("Hãy đề xuất cách điều chỉnh các buổi tập tiếp theo.")
                                ])
                            ]),
                            "allowOther": .bool(true),
                            "otherLabel": .string("Yêu cầu khác…"),
                            "otherPlaceholder": .string("Bạn muốn Coach điều chỉnh như thế nào?"),
                            "status": .string("pending")
                        ])
                    ])
                )
            ], stopReason: "tool_use")
        }
    }

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
