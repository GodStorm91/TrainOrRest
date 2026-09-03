import XCTest
@testable import TrainOrRest

final class AnthropicSSEParserTests: XCTestCase {
    func testTextStreamFramesProduceOrderedEvents() {
        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1"}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Rest"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" today."}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        event: message_stop
        data: {"type":"message_stop"}

        """

        XCTAssertEqual(AnthropicSSEParser.parse(sse), [
            .messageStart,
            .contentBlockStart(index: 0, kind: .text),
            .textDelta(index: 0, "Rest"),
            .textDelta(index: 0, " today."),
            .contentBlockStop(index: 0),
            .messageDelta(stopReason: "end_turn"),
            .messageStop
        ])
    }

    func testToolUseFramesProduceInputJSONDeltas() {
        let sse = """
        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"propose_plan_adjustment","input":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"changes\\":["}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"]}"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        """

        XCTAssertEqual(AnthropicSSEParser.parse(sse), [
            .contentBlockStart(index: 1, kind: .toolUse(id: "toolu_1", name: "propose_plan_adjustment")),
            .inputJSONDelta(index: 1, #"{"changes":["#),
            .inputJSONDelta(index: 1, #"]}"#),
            .contentBlockStop(index: 1)
        ])
    }

    func testSplitFrameAcrossFeedCallsBuffersUntilComplete() {
        var parser = AnthropicSSEParser()

        XCTAssertTrue(parser.feed("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",").isEmpty)
        XCTAssertEqual(
            parser.feed("\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}\n\n"),
            [.textDelta(index: 0, "Hi")]
        )
    }

    func testTransportKeepAliveFramesAreIgnored() {
        let events = AnthropicSSEParser.parse("""
        : keep-alive

        event: ping

        event: ping
        data: {"type":"ping"}

        """)

        XCTAssertEqual(events, [.ping])
    }


    func testLineSeparatedFramesDoNotCollapseIntoMalformedJSON() {
        var parser = AnthropicSSEParser()
        var events: [AnthropicStreamEvent] = []
        for line in [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\"}}",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}"
        ] {
            events += parser.feed(line + "\n")
        }
        events += parser.finish()

        XCTAssertEqual(events, [
            .messageStart,
            .textDelta(index: 0, "Hi"),
            .messageStop
        ])
    }

    func testBlankPingDataIsIgnored() {
        let events = AnthropicSSEParser.parse("""
        event: ping
        data:

        """)

        XCTAssertEqual(events, [])
    }

    func testEventOnlyFramesAreIgnored() {
        let events = AnthropicSSEParser.parse("""
        event: metadata

        event: ping

        event: message_stop
        data: {"type":"message_stop"}

        """)

        XCTAssertEqual(events, [.messageStop])
    }

    func testStructuralEventFallsBackToEventNameWhenPayloadShapeChanges() {
        let events = AnthropicSSEParser.parse("""
        event: message_stop
        data: {"future_type":"message_stop","extra":{"shape":"changed"}}

        """)

        XCTAssertEqual(events, [.messageStop])
    }

    func testUnsupportedContentBlockIsIgnored() {
        let events = AnthropicSSEParser.parse("""
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hidden"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Visible answer."}}

        """)

        XCTAssertEqual(events, [
            .contentBlockStop(index: 0),
            .contentBlockStart(index: 1, kind: .text),
            .textDelta(index: 1, "Visible answer.")
        ])
    }

    func testUnsupportedContentDeltaIsIgnored() {
        let events = AnthropicSSEParser.parse("""
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":{"type":"char_location","cited_text":"x"}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Still useful."}}

        """)

        XCTAssertEqual(events, [.textDelta(index: 0, "Still useful.")])
    }

    func testMalformedDataEmitsError() {
        let events = AnthropicSSEParser.parse("""
        event: message_start
        data: {not-json}

        """)

        XCTAssertEqual(events.count, 1)
        if case .error = events[0] {} else {
            XCTFail("Expected parser error")
        }
    }
}
