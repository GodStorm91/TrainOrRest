import XCTest
@testable import TrainOrRest

final class CoachStreamAccumulatorTests: XCTestCase {
    func testTextOnlySequenceEmitsOrderedTextDeltasAndMessageDone() async {
        let accumulator = CoachStreamAccumulator()

        let outputs = await ingest([
            .messageStart,
            .contentBlockStart(index: 0, kind: .text),
            .textDelta(index: 0, "Rest"),
            .textDelta(index: 0, " today."),
            .contentBlockStop(index: 0),
            .messageDelta(stopReason: "end_turn"),
            .messageStop
        ], into: accumulator)

        XCTAssertEqual(outputs, [
            .textDelta("Rest"),
            .textDelta(" today."),
            .messageDone(stopReason: "end_turn")
        ])
    }

    func testPlanEditDraftToolEmitsIntentOnlyAtContentBlockStop() async {
        let accumulator = CoachStreamAccumulator()
        var outputs: [CoachStreamEvent] = []

        outputs += await accumulator.ingest(.contentBlockStart(
            index: 0,
            kind: .toolUse(id: "toolu_1", name: "propose_plan_adjustment")
        ))
        outputs += await accumulator.ingest(.inputJSONDelta(index: 0, #"{"changes":["#))
        outputs += await accumulator.ingest(.inputJSONDelta(index: 0, #"{"date":"2026-07-11","action":"rest"}"#))
        XCTAssertTrue(outputs.isEmpty, "tool JSON deltas must not emit partial intents")

        outputs += await accumulator.ingest(.inputJSONDelta(index: 0, #"]}"#))
        XCTAssertTrue(outputs.isEmpty, "complete JSON still waits for content_block_stop")

        outputs += await accumulator.ingest(.contentBlockStop(index: 0))

        XCTAssertEqual(outputs, [
            .intentFinal(PlanEditIntent(proposal: .init(changes: [
                .init(date: "2026-07-11", action: .rest)
            ])))
        ])
    }

    func testCiteRuleToolEmitsRuleRefAtStop() async {
        let accumulator = CoachStreamAccumulator()

        let outputs = await ingest([
            .contentBlockStart(index: 0, kind: .toolUse(id: "toolu_2", name: "cite_rule")),
            .inputJSONDelta(index: 0, #"{"code":"R4"}"#),
            .contentBlockStop(index: 0)
        ], into: accumulator)

        XCTAssertEqual(outputs, [.ruleRefFinal("R4")])
    }

    func testExplainOnlyToolEmitsDecodedExplanationAtStop() async {
        let accumulator = CoachStreamAccumulator()
        let explanation = CoachExplanation(
            summary: "Rest today.",
            evidenceNotes: ["HRV low", "Sleep short"],
            uncertainty: nil,
            askableFollowups: ["What should I do instead?"]
        )

        let outputs = await ingest([
            .contentBlockStart(index: 0, kind: .toolUse(id: "toolu_3", name: "explain_only")),
            .inputJSONDelta(index: 0, #"{"summary":"Rest today.","#),
            .inputJSONDelta(index: 0, #""evidenceNotes":["HRV low","Sleep short"],"#),
            .inputJSONDelta(index: 0, #""askableFollowups":["What should I do instead?"]}"#),
            .contentBlockStop(index: 0)
        ], into: accumulator)

        XCTAssertEqual(outputs, [.explanationFinal(explanation)])
    }

    func testMalformedToolJSONAtStopEmitsErrorAndNoIntent() async {
        let accumulator = CoachStreamAccumulator()

        let outputs = await ingest([
            .contentBlockStart(index: 0, kind: .toolUse(id: "toolu_bad", name: "propose_plan_adjustment")),
            .inputJSONDelta(index: 0, #"{"changes":["#),
            .contentBlockStop(index: 0)
        ], into: accumulator)

        XCTAssertEqual(outputs, [.messageError("Couldn't read that proposal")])
    }

    func testMessageStopWithOpenToolDropsBlockAndEmitsStoppedOnly() async {
        let accumulator = CoachStreamAccumulator()

        let outputs = await ingest([
            .contentBlockStart(index: 0, kind: .toolUse(id: "toolu_open", name: "propose_plan_adjustment")),
            .inputJSONDelta(index: 0, #"{"changes":[{"date":"2026-07-11","action":"rest"}]}"#),
            .messageDelta(stopReason: "tool_use"),
            .messageStop
        ], into: accumulator)

        XCTAssertEqual(outputs, [.messageStopped])
    }

    private func ingest(
        _ events: [AnthropicStreamEvent],
        into accumulator: CoachStreamAccumulator
    ) async -> [CoachStreamEvent] {
        var outputs: [CoachStreamEvent] = []
        for event in events {
            outputs += await accumulator.ingest(event)
        }
        return outputs
    }
}
