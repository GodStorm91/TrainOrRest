import XCTest
@testable import TrainOrRest

/// Raw Messages-API contract: block round trips, tool schema, and strict dates.
@MainActor
final class CoachToolContractTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    // MARK: - Lossless block round trip

    /// Thinking, redacted thinking and future block types must survive the tool
    /// loop byte-for-byte; collapsing them breaks the assistant replay.
    func testUnknownAssistantBlocksRoundTripUnchanged() throws {
        let raw = """
        [
          {"type":"thinking","thinking":"weighing the ramp","signature":"sig-abc"},
          {"type":"redacted_thinking","data":"opaque-payload"},
          {"type":"text","text":"Adding a tempo."},
          {"type":"tool_use","id":"toolu_1","name":"propose_plan_adjustment","input":{"changes":[]}},
          {"type":"future_block","shape":{"nested":[1,2]}}
        ]
        """.data(using: .utf8)!

        let blocks = try JSONDecoder().decode([ClaudeContentBlock].self, from: raw)
        XCTAssertEqual(blocks.count, 5)
        if case .passthrough = blocks[0] {} else { XCTFail("thinking must be preserved, not decoded") }
        if case .passthrough = blocks[1] {} else { XCTFail("redacted_thinking must be preserved") }
        XCTAssertEqual(blocks[2], .text("Adding a tempo."))
        if case .passthrough = blocks[4] {} else { XCTFail("unknown block must be preserved") }

        let reencoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(blocks))
        let original = try JSONDecoder().decode(JSONValue.self, from: raw)
        XCTAssertEqual(reencoded, original, "assistant blocks must replay unchanged and in order")
    }

    func testToolUseIdentityAndOrderSurviveReplay() throws {
        let raw = """
        {"content":[
          {"type":"thinking","thinking":"t","signature":"s"},
          {"type":"tool_use","id":"toolu_42","name":"propose_plan_adjustment","input":{"changes":[]}}
        ],"stop_reason":"tool_use"}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: raw)
        XCTAssertEqual(response.stopReason, "tool_use")

        let replay = ClaudeMessageParam(role: "assistant", content: response.content)
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(replay))
        guard case .object(let message) = encoded, case .array(let content)? = message["content"] else {
            return XCTFail("replayed message must carry its content array")
        }
        XCTAssertEqual(content.count, 2, "no block may be dropped before the tool result")
        guard case .object(let first) = content[0], case .string("thinking")? = first["type"] else {
            return XCTFail("thinking must stay first")
        }
        guard case .object(let second) = content[1], case .string("toolu_42")? = second["id"] else {
            return XCTFail("tool_use id must be preserved")
        }
    }

    // MARK: - Tool schema

    func testToolSchemaAdvertisesCreateWithClosedNestedObjects() throws {
        guard case .object(let schema) = CoachTools.tool.inputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let changes)? = properties["changes"],
              case .object(let item)? = changes["items"],
              case .object(let itemProperties)? = item["properties"],
              case .object(let action)? = itemProperties["action"],
              case .array(let actions)? = action["enum"],
              case .object(let workout)? = itemProperties["workout"],
              case .object(let workoutProperties)? = workout["properties"],
              case .object(let kind)? = workoutProperties["kind"],
              case .array(let kinds)? = kind["enum"]
        else { return XCTFail("tool schema shape changed") }

        XCTAssertEqual(schema["additionalProperties"], .bool(false))
        XCTAssertEqual(item["additionalProperties"], .bool(false))
        XCTAssertEqual(workout["additionalProperties"], .bool(false))
        XCTAssertTrue(actions.contains(.string("create")))
        XCTAssertEqual(kinds, ["easy", "long", "tempo", "intervals"].map(JSONValue.string))
        XCTAssertFalse(kinds.contains(.string("race")), "race must never be creatable")
    }

    // MARK: - Exact payload decoding

    func testExactTempoPayloadDecodes() throws {
        let json = """
        {"changes":[{"date":"2026-07-11","action":"create","workout":{"kind":"tempo","blocks":[{"repeat_count":1,"steps":[{"role":"warm_up","target_type":"distance_km","target_value":2,"pace_zone":"easy"},{"role":"work","target_type":"distance_km","target_value":5,"pace_zone":"threshold"},{"role":"cool_down","target_type":"distance_km","target_value":2,"pace_zone":"easy"}]}]}}]}
        """.data(using: .utf8)!
        let proposal = try JSONDecoder().decode(PlanAdjustmentProposal.self, from: json)
        let workout = try XCTUnwrap(proposal.changes.first?.workout)

        XCTAssertEqual(proposal.changes.first?.action, .create)
        XCTAssertEqual(workout.kind, "tempo")
        XCTAssertEqual(workout.blocks.count, 1)
        XCTAssertEqual(workout.blocks[0].repeatCount, 1)
        XCTAssertEqual(workout.blocks[0].steps.map(\.role), ["warm_up", "work", "cool_down"])
        XCTAssertEqual(workout.blocks[0].steps[1].paceZone, "threshold")
        XCTAssertEqual(workout.blocks[0].steps[1].targetValue, 5)
    }

    func testExactIntervalPayloadDecodesRepeatsAndDurationRecovery() throws {
        let json = """
        {"changes":[{"date":"2026-07-11","action":"create","workout":{"kind":"intervals","blocks":[{"repeat_count":1,"steps":[{"role":"warm_up","target_type":"distance_km","target_value":2,"pace_zone":"easy"}]},{"repeat_count":5,"steps":[{"role":"work","target_type":"distance_km","target_value":1,"pace_zone":"interval"},{"role":"recovery","target_type":"duration_seconds","target_value":150,"pace_zone":"easy"}]},{"repeat_count":1,"steps":[{"role":"cool_down","target_type":"distance_km","target_value":2,"pace_zone":"easy"}]}]}}]}
        """.data(using: .utf8)!
        let workout = try XCTUnwrap(
            try JSONDecoder().decode(PlanAdjustmentProposal.self, from: json).changes.first?.workout
        )

        XCTAssertEqual(workout.blocks.count, 3)
        XCTAssertEqual(workout.blocks[1].repeatCount, 5)
        XCTAssertEqual(workout.blocks[1].steps[0].paceZone, "interval")
        XCTAssertEqual(workout.blocks[1].steps[1].targetType, "duration_seconds")
        XCTAssertEqual(workout.blocks[1].steps[1].targetValue, 150)
    }

    // MARK: - Strict dates

    func testCanonicalDateParses() throws {
        let date = try CoachTools.parseDay("2026-07-11", calendar: calendar)
        XCTAssertEqual(date, PlanEngineTestSupport.date(2026, 7, 11, hour: 0))
    }

    /// 2026-07-10 is a Friday, so "Saturday" resolves to 2026-07-11.
    func testTodayAnchorNamesTheWeekdayUsedForRelativeResolution() {
        let friday = PlanEngineTestSupport.date(2026, 7, 10)
        let saturday = PlanEngineTestSupport.date(2026, 7, 11)
        XCTAssertEqual(CoachContextBuilder.weekdayName(friday, calendar: calendar), "Friday")
        XCTAssertEqual(CoachContextBuilder.day(saturday, calendar: calendar), "2026-07-11")
    }

    func testNoncanonicalDatesAreRejected() {
        for value in [
            "2026-7-11",             // unpadded
            "2026-02-30",            // rollover
            "2026-13-01",            // impossible month
            "26-07-11",              // short year
            "11/07/2026",            // locale text
            "2026-07-11T00:00:00Z",  // timestamp
            "tomorrow",
            "",
            " 2026-07-11"
        ] {
            XCTAssertThrowsError(
                try CoachTools.parseDay(value, calendar: calendar),
                "\(value) must be rejected"
            )
        }
    }
}
