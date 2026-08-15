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

    private func stream(_ events: [AnthropicStreamEvent]) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
