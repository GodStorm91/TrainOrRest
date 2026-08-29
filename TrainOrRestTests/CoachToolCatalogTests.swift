import XCTest
@testable import TrainOrRest

@MainActor
final class CoachToolCatalogTests: XCTestCase {
    func testToolsHaveExpectedNames() {
        XCTAssertEqual(CoachToolCatalog.explainOnly.name, "explain_only")
        XCTAssertEqual(CoachToolCatalog.planEditDraft.name, "propose_plan_adjustment")
        XCTAssertEqual(CoachToolCatalog.ruleRef.name, "cite_rule")
    }

    func testToolsOmitPlanEditDraftWhenProposalsAreDisallowed() {
        XCTAssertEqual(
            CoachToolCatalog.tools(allowProposals: false).map(\.name),
            ["coach_response", "explain_only", "cite_rule"]
        )
        XCTAssertEqual(
            CoachToolCatalog.tools(allowProposals: true).map(\.name),
            ["coach_response", "explain_only", "propose_plan_adjustment", "cite_rule"]
        )
    }

    func testToolChoiceEncodesAnthropicJSON() throws {
        XCTAssertEqual(try encodedJSON(CoachToolCatalog.ToolChoice.auto), .object(["type": .string("auto")]))
        XCTAssertEqual(try encodedJSON(CoachToolCatalog.ToolChoice.any), .object(["type": .string("any")]))
        XCTAssertEqual(
            try encodedJSON(CoachToolCatalog.ToolChoice.tool(name: "explain_only")),
            .object(["type": .string("tool"), "name": .string("explain_only")])
        )
    }

    func testClaudeRequestIncludesToolChoiceWhenProvided() throws {
        let request = ClaudeRequest(
            model: "claude-test",
            system: "Reply with structured content.",
            tools: [CoachToolCatalog.coachResponse],
            toolChoice: .tool(name: CoachToolCatalog.coachResponseName),
            messages: [ClaudeMessageParam(role: "user", content: [.text("Review this run.")])]
        )

        guard case .object(let json) = try encodedJSON(request) else {
            return XCTFail("ClaudeRequest must encode as an object")
        }

        XCTAssertEqual(
            json["tool_choice"],
            .object(["type": .string("tool"), "name": .string(CoachToolCatalog.coachResponseName)])
        )
    }

    func testExplainOnlySchemaAndPayloadRoundTrip() throws {
        guard case .object(let schema) = CoachToolCatalog.explainOnly.inputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let evidenceNotes)? = properties["evidenceNotes"],
              case .array(let required)? = schema["required"] else {
            return XCTFail("explain_only schema shape changed")
        }

        XCTAssertEqual(CoachToolCatalog.explainOnly.name, "explain_only")
        XCTAssertEqual(schema["additionalProperties"], .bool(false))
        XCTAssertEqual(evidenceNotes["type"], .string("array"))
        XCTAssertEqual(
            required,
            ["summary", "evidenceNotes", "askableFollowups"].map(JSONValue.string)
        )

        let explanation = CoachExplanation(
            summary: "Rest today.",
            evidenceNotes: ["HRV below baseline", "Poor sleep"],
            uncertainty: "Workout freshness is stale.",
            askableFollowups: ["What would make this a train day?"]
        )

        let decoded = try JSONDecoder().decode(CoachExplanation.self, from: JSONEncoder().encode(explanation))
        XCTAssertEqual(decoded, explanation)
    }

    private func encodedJSON<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}
