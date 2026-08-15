import XCTest
@testable import TrainOrRest

final class CoachStreamingIntegrationTests: XCTestCase {
    func testParserEventsDriveAccumulatorCoachEvents() async {
        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1"}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"explain_only","input":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"summary\\":\\"Rest today.\\","}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"evidenceNotes\\":[\\"HRV low\\"],\\"askableFollowups\\":[\\"What about tomorrow?\\"]}"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let accumulator = CoachStreamAccumulator()
        var outputs: [CoachStreamEvent] = []

        for event in AnthropicSSEParser.parse(sse) {
            outputs += await accumulator.ingest(event)
        }

        XCTAssertEqual(outputs, [
            .explanationFinal(CoachExplanation(
                summary: "Rest today.",
                evidenceNotes: ["HRV low"],
                uncertainty: nil,
                askableFollowups: ["What about tomorrow?"]
            )),
            .messageDone(stopReason: "tool_use")
        ])
    }
}
