import Foundation

struct CoachExplanation: Codable, Equatable {
    var summary: String
    var evidenceNotes: [String]
    var uncertainty: String?
    var askableFollowups: [String]
}

enum CoachToolCatalog {
    static let explainOnlyName = "explain_only"
    static let planEditDraftName = "propose_plan_adjustment"
    static let ruleRefName = "cite_rule"

    static var explainOnly: ClaudeTool {
        ClaudeTool(
            name: explainOnlyName,
            description: """
            Explain the readiness or plan decision using only supplied evidence. Return a short \
            summary, concrete evidence notes, any uncertainty, and useful follow-up questions.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "summary": .object([
                        "type": .string("string"),
                        "description": .string("Short user-facing explanation.")
                    ]),
                    "evidenceNotes": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Evidence notes grounded in the supplied snapshot.")
                    ]),
                    "uncertainty": .object([
                        "type": .string("string"),
                        "description": .string("Optional uncertainty or missing context.")
                    ]),
                    "askableFollowups": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Short follow-up questions the user can ask.")
                    ])
                ]),
                "required": .array(["summary", "evidenceNotes", "askableFollowups"].map(JSONValue.string))
            ])
        )
    }

    @MainActor
    static var planEditDraft: ClaudeTool {
        CoachTools.tool
    }

    static var ruleRef: ClaudeTool {
        ClaudeTool(
            name: ruleRefName,
            description: "Cite a deterministic local readiness rule by code.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "code": .object([
                        "type": .string("string"),
                        "description": .string("Rule code, formatted like R4.")
                    ])
                ]),
                "required": .array([.string("code")])
            ])
        )
    }

    @MainActor
    static func tools(allowProposals: Bool) -> [ClaudeTool] {
        if allowProposals {
            return [explainOnly, planEditDraft, ruleRef]
        }
        return [explainOnly, ruleRef]
    }

    enum ToolChoice: Encodable, Equatable {
        case auto
        case any
        case tool(name: String)

        private enum CodingKeys: String, CodingKey {
            case type, name
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .auto:
                try container.encode("auto", forKey: .type)
            case .any:
                try container.encode("any", forKey: .type)
            case .tool(let name):
                try container.encode("tool", forKey: .type)
                try container.encode(name, forKey: .name)
            }
        }
    }
}
