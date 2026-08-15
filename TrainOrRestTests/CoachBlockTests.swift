import XCTest
@testable import TrainOrRest

final class CoachBlockTests: XCTestCase {
    func testModelBlockDecodesProseRuleRefAndPlanEditDraft() throws {
        let proposalJSON = """
        {"type":"plan_edit_draft","proposal":{"changes":[{"date":"2026-07-11","action":"rest"}]}}
        """.data(using: .utf8)!

        let prose = try JSONDecoder().decode(CoachModelBlock.self, from: #"{"type":"prose","text":"Rest today."}"#.data(using: .utf8)!)
        let rule = try JSONDecoder().decode(CoachModelBlock.self, from: #"{"type":"rule_ref","code":"R4"}"#.data(using: .utf8)!)
        let draft = try JSONDecoder().decode(CoachModelBlock.self, from: proposalJSON)

        XCTAssertEqual(prose, .prose("Rest today."))
        XCTAssertEqual(rule, .ruleRef("R4"))
        XCTAssertEqual(draft, .planEditDraft(PlanEditIntent(proposal: .init(changes: [
            .init(date: "2026-07-11", action: .rest)
        ]))))
    }

    func testModelBlockCannotDecodeEngineOwnedArtifact() {
        for type in ["engine_verdict", "readiness_rationale", "validated_proposal", "applied_edit_receipt"] {
            let data = #"{"type":"\#(type)","summary":"Model claimed system artifact"}"#.data(using: .utf8)!

            XCTAssertThrowsError(try JSONDecoder().decode(CoachModelBlock.self, from: data))
        }
    }

    func testAsCoachBlockMapsOnlyModelAuthorableCases() throws {
        let proposal = PlanAdjustmentProposal(changes: [
            .init(date: "2026-07-11", action: .downgrade)
        ])

        XCTAssertEqual(CoachModelBlock.prose("Why: fatigue is high.").asCoachBlock(), .prose("Why: fatigue is high."))
        XCTAssertEqual(CoachModelBlock.ruleRef("R4").asCoachBlock(), .ruleRef("R4"))
        XCTAssertEqual(
            CoachModelBlock.planEditDraft(PlanEditIntent(proposal: proposal)).asCoachBlock(),
            .planEditDraft(PlanEditIntent(proposal: proposal))
        )
    }
}
