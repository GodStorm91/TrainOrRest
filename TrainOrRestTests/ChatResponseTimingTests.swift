import SwiftData
import XCTest
@testable import TrainOrRest

/// The chat footer that tells a user when a reply landed and how long they waited for it.
@MainActor
final class ChatResponseTimingTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 1, 5)
    private let sent = Date(timeIntervalSince1970: 1_767_600_000)

    // MARK: - Duration arithmetic

    func testDurationIsTheWaitBetweenSendAndReply() {
        let message = assistantMessage()
        message.markCompleted(at: sent.addingTimeInterval(4.23))

        XCTAssertEqual(try XCTUnwrap(message.generationDuration), 4.23, accuracy: 0.001)
    }

    func testRetryReportsItsOwnWaitNotTheIdleGapSinceTheFirstSend() throws {
        let message = assistantMessage()
        message.generationStartedAt = sent.addingTimeInterval(600)
        message.markCompleted(at: sent.addingTimeInterval(608))

        XCTAssertEqual(try XCTUnwrap(message.generationDuration), 8, accuracy: 0.001)
    }

    func testUnfinishedTurnHasNoDuration() {
        let message = assistantMessage()
        message.assistantStatus = .streaming

        XCTAssertNil(message.generationDuration)
        XCTAssertNil(ChatBubble.responseTimingText(for: message, language: .en))
    }

    func testTurnSavedBeforeTheFieldExistedShowsNoFooter() {
        let message = assistantMessage()
        message.assistantStatus = .completed
        message.completedAt = nil

        XCTAssertNil(ChatBubble.responseTimingText(for: message, language: .en))
    }

    func testClockMovingBackwardsDuringATurnIsDiscardedRatherThanShownNegative() {
        let message = assistantMessage()
        message.markCompleted(at: sent.addingTimeInterval(-30))

        XCTAssertNil(message.generationDuration)
        XCTAssertNil(ChatBubble.responseTimingText(for: message, language: .en))
    }

    func testUserMessagesNeverCarryTiming() {
        let message = ChatMessage(role: .user, text: "Should I run today?", date: sent)
        message.completedAt = sent.addingTimeInterval(2)

        XCTAssertNil(ChatBubble.responseTimingText(for: message, language: .en))
    }

    // MARK: - Rendering

    func testFooterPairsLandingTimeWithElapsedSeconds() throws {
        let message = assistantMessage()
        message.markCompleted(at: sent.addingTimeInterval(4.23))

        let timing = try XCTUnwrap(ChatBubble.responseTimingText(for: message, language: .en))
        let expectedTime = sent.addingTimeInterval(4.23)
            .formatted(.dateTime.hour().minute().locale(CoachLanguage.en.uiLocale))
        XCTAssertEqual(timing.label, "\(expectedTime) · 4.2s")
        XCTAssertEqual(timing.accessibilityLabel, "Answered at \(expectedTime), took 4.2s")
    }

    func testInstantShortcutRepliesReadAsATenthRatherThanZero() {
        XCTAssertEqual(CoachLanguage.en.coachResponseDurationLabel(seconds: 0.004), "0.1s")
    }

    func testLongTurnsDropTheDecimal() {
        XCTAssertEqual(CoachLanguage.en.coachResponseDurationLabel(seconds: 182.4), "182s")
        XCTAssertEqual(CoachLanguage.en.coachResponseDurationLabel(seconds: 59.94), "59.9s")
    }

    func testDurationUsesTheUnitAndDecimalMarkOfEachLanguage() {
        XCTAssertEqual(CoachLanguage.en.coachResponseDurationLabel(seconds: 4.23), "4.2s")
        XCTAssertEqual(CoachLanguage.vi.coachResponseDurationLabel(seconds: 4.23), "4,2 giây")
        XCTAssertEqual(CoachLanguage.ja.coachResponseDurationLabel(seconds: 4.23), "4.2秒")
    }

    // MARK: - Store wiring

    func testCompletedTurnIsStampedSoTheFooterCanRender() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = TimingCoachClient()
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.submitTestTurn(text: "Should I train or rest tomorrow?", model: "claude-test", apiKey: "test-key", in: context)

        let assistant = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant }
        )
        XCTAssertEqual(assistant.assistantStatus, .completed)
        let duration = try XCTUnwrap(assistant.generationDuration)
        XCTAssertGreaterThanOrEqual(duration, 0)
        XCTAssertLessThan(duration, 60)
        XCTAssertNotNil(ChatBubble.responseTimingText(for: assistant, language: .en))
    }

    func testFailedTurnIsNotStamped() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMinimalTrainingData(in: context)
        let client = TimingCoachClient(error: ClaudeClientError.connectionLost)
        let store = CoachChatStore(client: client, calendar: calendar, now: { self.today })

        await store.submitTestTurn(text: "Should I train or rest tomorrow?", model: "claude-test", apiKey: "test-key", in: context)

        let assistant = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatMessage>()).first { $0.role == .assistant }
        )
        XCTAssertEqual(assistant.assistantStatus, .failed)
        XCTAssertNil(assistant.completedAt)
    }

    // MARK: - Helpers

    private func assistantMessage() -> ChatMessage {
        ChatMessage(role: .assistant, text: "Rest tomorrow.", date: sent)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CompletedActivity.self, DailyWellness.self, SyncState.self,
            Goal.self, TrainingPlan.self, PlannedWorkout.self,
            DailyReadiness.self, DailyCheckIn.self, PlanSnapshot.self, ChatThread.self, ChatMessage.self,
            CoachRequestSnapshot.self, CoachMemoryItem.self, CoachPromptSuggestionRecord.self
        ])
        let configuration = ModelConfiguration("ChatResponseTimingTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
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
private final class TimingCoachClient: ClaudeServicing {
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func send(_ request: ClaudeRequest, credential: CoachCredential) async throws -> ClaudeResponse {
        if let error { throw error }
        return Self.answer
    }

    func stream(_ request: ClaudeRequest, credential: CoachCredential) async throws -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        if let error { throw error }
        return AsyncThrowingStream { continuation in
            continuation.yield(.messageStart)
            for (index, block) in Self.answer.content.enumerated() {
                guard case let .toolUse(id, name, input) = block else { continue }
                continuation.yield(.contentBlockStart(index: index, kind: .toolUse(id: id, name: name)))
                if let data = try? JSONEncoder().encode(input), let json = String(data: data, encoding: .utf8) {
                    continuation.yield(.inputJSONDelta(index: index, json))
                }
                continuation.yield(.contentBlockStop(index: index))
            }
            continuation.yield(.messageDelta(stopReason: Self.answer.stopReason))
            continuation.yield(.messageStop)
            continuation.finish()
        }
    }

    private static let answer = ClaudeResponse(
        content: [
            .toolUse(
                id: "toolu_card",
                name: CoachToolCatalog.coachResponseName,
                input: .object([
                    "content": .string("Rest tomorrow and reassess in the morning."),
                    "title": .string("Rest tomorrow"),
                    "summary": .string("Readiness is low, so take the day off.")
                ])
            )
        ],
        stopReason: "tool_use"
    )
}
