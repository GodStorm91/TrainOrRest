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
            Return the user-facing Coach message and, only when the user needs to choose between \
            next steps, an optional structured single-choice interaction. Use natural language in \
            content. Do not encode choices in the prose alone when a decision is requested.
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
                        "description": .string("One concise decision-relevant conclusion, at most two lines.")
                    ]),
                    "summary": .object([
                        "type": .string("string"),
                        "description": .string("Two or three short sentences explaining why. Do not put all analysis here.")
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
                "required": .array([.string("content")])
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
