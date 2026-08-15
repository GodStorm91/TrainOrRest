import Foundation

enum CoachBlock: Equatable {
    // Model-authorable blocks.
    case prose(String)
    case ruleRef(String)
    case planEditDraft(PlanEditIntent)

    // Engine-owned blocks. These are created only from local engine and
    // validator outputs, never from the model-facing schema.
    case engineVerdict(EngineVerdict)
    case readinessRationale(ReadinessRationale)
    case validatedProposal(ValidatedProposal)
    case appliedEditReceipt(AppliedEditReceipt)
}

struct PlanEditIntent: Codable, Equatable {
    var proposal: PlanAdjustmentProposal
}

struct EngineVerdict: Equatable {
    var id: UUID
    var readinessVersion: Int
    var ruleCode: String?
    var summary: String

    init(id: UUID = UUID(), readinessVersion: Int, ruleCode: String?, summary: String) {
        self.id = id
        self.readinessVersion = readinessVersion
        self.ruleCode = ruleCode
        self.summary = summary
    }
}

struct ReadinessRationale: Equatable {
    var id: UUID
    var readinessVersion: Int
    var signalIDs: [String]
    var summary: String

    init(id: UUID = UUID(), readinessVersion: Int, signalIDs: [String], summary: String) {
        self.id = id
        self.readinessVersion = readinessVersion
        self.signalIDs = signalIDs
        self.summary = summary
    }
}

struct ValidatedProposal: Equatable {
    var id: UUID
    var planVersion: Int
    var intent: PlanEditIntent
    var summary: String

    init(id: UUID = UUID(), planVersion: Int, intent: PlanEditIntent, summary: String) {
        self.id = id
        self.planVersion = planVersion
        self.intent = intent
        self.summary = summary
    }
}

struct AppliedEditReceipt: Equatable {
    var id: UUID
    var proposalID: UUID
    var planVersion: Int
    var summary: String

    init(id: UUID = UUID(), proposalID: UUID, planVersion: Int, summary: String) {
        self.id = id
        self.proposalID = proposalID
        self.planVersion = planVersion
        self.summary = summary
    }
}

enum CoachModelBlock: Decodable, Equatable {
    case prose(String)
    case ruleRef(String)
    case planEditDraft(PlanEditIntent)

    private enum CodingKeys: String, CodingKey {
        case type, text, code, proposal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "prose":
            self = .prose(try container.decode(String.self, forKey: .text))
        case "rule_ref", "ruleRef":
            self = .ruleRef(try container.decode(String.self, forKey: .code))
        case "plan_edit_draft", "planEditDraft":
            let proposal = try container.decode(PlanAdjustmentProposal.self, forKey: .proposal)
            self = .planEditDraft(PlanEditIntent(proposal: proposal))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported coach model block type: \(type)"
            )
        }
    }

    func asCoachBlock() -> CoachBlock {
        switch self {
        case .prose(let text):
            return .prose(text)
        case .ruleRef(let code):
            return .ruleRef(code)
        case .planEditDraft(let intent):
            return .planEditDraft(intent)
        }
    }
}
