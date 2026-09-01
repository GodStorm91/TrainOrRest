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
    static let coachResponseName = "coach_response"

    static var coachResponse: ClaudeTool {
        ClaudeTool(
            name: coachResponseName,
            description: """
            Return the user-facing Coach reply as a structured answer card. Always provide title, \
            summary, and content: title is the one-line conclusion, summary is the short reason, and \
            content is the natural-language message shown in the chat bubble. Use recommendations and \
            details for depth. Include a single-choice interaction only when the user must choose \
            between next steps; never encode choices in the prose alone.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("Natural-language assistant message shown in the chat bubble.")
                    ]),
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("One concise conclusion for the answer card, at most two lines. Always provide it.")
                    ]),
                    "summary": .object([
                        "type": .string("string"),
                        "description": .string("Two or three short sentences of reasoning for the answer card. Always provide it; do not put all analysis here.")
                    ]),
                    "safetyNote": .object([
                        "type": .string("string"),
                        "description": .string("Urgent safety-critical advice; shown before actions and never hidden. Omit if none.")
                    ]),
                    "recommendations": .object([
                        "type": .string("array"),
                        "maxItems": .number(6),
                        "items": .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "id": .object(["type": .string("string")]),
                                "title": .object(["type": .string("string")]),
                                "description": .object(["type": .string("string")]),
                                "priority": .object([
                                    "type": .string("integer"),
                                    "minimum": .number(1)
                                ])
                            ]),
                            "required": .array(["id", "title", "priority"].map(JSONValue.string))
                        ])
                    ]),
                    "details": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "title": .object(["type": .string("string")]),
                            "sections": .object([
                                "type": .string("array"),
                                "items": .object([
                                    "type": .string("object"),
                                    "additionalProperties": .bool(false),
                                    "properties": .object([
                                        "id": .object(["type": .string("string")]),
                                        "title": .object(["type": .string("string")]),
                                        "markdown": .object(["type": .string("string")])
                                    ]),
                                    "required": .array(["id", "title", "markdown"].map(JSONValue.string))
                                ])
                            ])
                        ]),
                        "required": .array(["title", "sections"].map(JSONValue.string))
                    ]),
                    "followUps": .object([
                        "type": .string("array"),
                        "maxItems": .number(3),
                        "items": .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "id": .object(["type": .string("string")]),
                                "label": .object(["type": .string("string")]),
                                "value": .object(["type": .string("string")])
                            ]),
                            "required": .array(["id", "label", "value"].map(JSONValue.string))
                        ])
                    ]),
                    "interaction": interactionSchema
                ]),
                "required": .array([.string("content"), .string("title"), .string("summary")])
            ])
        )
    }

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
            return [coachResponse, explainOnly, planEditDraft, ruleRef]
        }
        return [coachResponse, explainOnly, ruleRef]
    }

    private static var interactionSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "type": .object([
                    "type": .string("string"),
                    "enum": .array([.string("single_choice")])
                ]),
                "title": .object(["type": .string("string")]),
                "options": .object([
                    "type": .string("array"),
                    "minItems": .number(2),
                    "maxItems": .number(4),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "id": .object(["type": .string("string")]),
                            "label": .object(["type": .string("string")]),
                            "description": .object(["type": .string("string")]),
                            "value": .object(["type": .string("string")])
                        ]),
                        "required": .array(["id", "label", "value"].map(JSONValue.string))
                    ])
                ]),
                "allowOther": .object(["type": .string("boolean")]),
                "otherLabel": .object(["type": .string("string")]),
                "otherPlaceholder": .object(["type": .string("string")]),
                "status": .object([
                    "type": .string("string"),
                    "enum": .array([.string("pending"), .string("resolved")])
                ]),
                "selectedOptionId": .object(["type": .string("string")])
            ]),
            "required": .array(["id", "type", "options", "allowOther"].map(JSONValue.string))
        ])
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
