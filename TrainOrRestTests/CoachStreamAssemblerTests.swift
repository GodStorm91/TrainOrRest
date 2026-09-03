import XCTest
@testable import TrainOrRest

final class CoachStreamAssemblerTests: XCTestCase {
    func testAssemblesTextOnlyResponseAndForwardsDeltas() async throws {
        var deltas: [String] = []
        let assembler = CoachStreamAssembler { delta in
            deltas.append(delta)
        }

        let assembled = try await assembler.assemble(stream([
            .messageStart,
            .contentBlockStart(index: 0, kind: .text),
            .textDelta(index: 0, "Rest"),
            .textDelta(index: 0, " today."),
            .contentBlockStop(index: 0),
            .messageDelta(stopReason: "end_turn"),
            .messageStop
        ]))

        XCTAssertEqual(assembled.response, ClaudeResponse(content: [.text("Rest today.")], stopReason: "end_turn"))
        XCTAssertNil(assembled.error)
        XCTAssertEqual(deltas, ["Rest", " today."])
    }

    func testAssemblesToolUseResponse() async throws {
        let assembled = try await CoachStreamAssembler().assemble(stream([
            .messageStart,
            .contentBlockStart(index: 0, kind: .toolUse(id: "toolu_1", name: "propose_plan_adjustment")),
            .inputJSONDelta(index: 0, #"{"changes":[{"#),
            .inputJSONDelta(index: 0, #""date":"2026-07-11","action":"rest"}]}"#),
            .contentBlockStop(index: 0),
            .messageDelta(stopReason: "tool_use"),
            .messageStop
        ]))

        XCTAssertEqual(assembled.response, ClaudeResponse(content: [
            .toolUse(id: "toolu_1", name: "propose_plan_adjustment", input: .object([
                "changes": .array([.object([
                    "date": .string("2026-07-11"),
                    "action": .string("rest")
                ])])
            ]))
        ], stopReason: "tool_use"))
        XCTAssertNil(assembled.error)
    }


    func testIgnoresOrphanedContentBlockStop() async throws {
        let assembled = try await CoachStreamAssembler().assemble(stream([
            .messageStart,
            .contentBlockStop(index: 0),
            .messageDelta(stopReason: "end_turn"),
            .messageStop
        ]))

        XCTAssertEqual(assembled.response, ClaudeResponse(content: [], stopReason: "end_turn"))
        XCTAssertNil(assembled.error)
    }

    func testRecoversTextDeltaWithoutContentBlockStart() async throws {
        var deltas: [String] = []
        let assembled = try await CoachStreamAssembler { delta in
            deltas.append(delta)
        }.assemble(stream([
            .messageStart,
            .textDelta(index: 0, "Recovered text."),
            .contentBlockStop(index: 0),
            .messageDelta(stopReason: "end_turn"),
            .messageStop
        ]))

        XCTAssertEqual(assembled.response, ClaudeResponse(content: [.text("Recovered text.")], stopReason: "end_turn"))
        XCTAssertNil(assembled.error)
        XCTAssertEqual(deltas, ["Recovered text."])
    }

    func testKeepsUnclosedTextAtStreamEnd() async throws {
        let assembled = try await CoachStreamAssembler().assemble(stream([
            .messageStart,
            .contentBlockStart(index: 0, kind: .text),
            .textDelta(index: 0, "Partial but useful."),
            .messageDelta(stopReason: "end_turn"),
            .messageStop
        ]))

        XCTAssertEqual(assembled.response, ClaudeResponse(content: [.text("Partial but useful.")], stopReason: "end_turn"))
        XCTAssertNil(assembled.error)
    }

    func testPropagatesMaxTokensStopReason() async throws {
        let assembled = try await CoachStreamAssembler().assemble(stream([
            .messageStart,
            .contentBlockStart(index: 0, kind: .text),
            .textDelta(index: 0, "Partial"),
            .contentBlockStop(index: 0),
            .messageDelta(stopReason: "max_tokens"),
            .messageStop
        ]))

        XCTAssertEqual(assembled.response.stopReason, "max_tokens")
    }

    func testUnclosedToolBlockAtStreamEndReportsTruncationNotError() async throws {
        let assembled = try await CoachStreamAssembler().assemble(stream([
            .messageStart,
            .contentBlockStart(index: 0, kind: .toolUse(id: "toolu_1", name: "propose_plan_adjustment")),
            .inputJSONDelta(index: 0, #"{"changes":[{"date":"2026-07-11","#),
            .messageDelta(stopReason: "max_tokens"),
            .messageStop
        ]))

        XCTAssertTrue(assembled.truncated)
        XCTAssertNil(assembled.error)
    }

    private func stream(_ events: [AnthropicStreamEvent]) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
