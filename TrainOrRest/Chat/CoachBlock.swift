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
    var verdict: ReadinessVerdict
    var score: Int?
    var signals: [ReadinessSignalSummary]
    var ruleIDs: [ReadinessRuleID]
    var summary: String
    var computedAt: Date?

    var signalIDs: [String] { signals.map(\.id) }

    init(
        id: UUID = UUID(),
        readinessVersion: Int,
        verdict: ReadinessVerdict,
        score: Int?,
        signals: [ReadinessSignalSummary],
        ruleIDs: [ReadinessRuleID],
        summary: String,
        computedAt: Date?
    ) {
        self.id = id
        self.readinessVersion = readinessVersion
        self.verdict = verdict
        self.score = score
        self.signals = signals
        self.ruleIDs = ruleIDs
        self.summary = summary
        self.computedAt = computedAt
    }

    init(id: UUID = UUID(), readinessVersion: Int, signalIDs: [String], summary: String) {
        self.init(
            id: id,
            readinessVersion: readinessVersion,
            verdict: .insufficientData,
            score: nil,
            signals: signalIDs.map { ReadinessSignalSummary(id: $0, label: $0, value: "Available", symbol: "waveform.path.ecg") },
            ruleIDs: [],
            summary: summary,
            computedAt: nil
        )
    }

    init(from readiness: DailyReadiness) {
        self.init(
            readinessVersion: Int(readiness.computedAt.timeIntervalSince1970),
            verdict: readiness.verdict,
            score: readiness.score,
            signals: Self.topSignals(from: readiness),
            ruleIDs: readiness.ruleIDs,
            summary: Self.summary(for: readiness),
            computedAt: readiness.computedAt
        )
    }

    private static func summary(for readiness: DailyReadiness) -> String {
        if let reason = readiness.reasons.first, !reason.isEmpty {
            return reason
        }
        if readiness.verdict == .insufficientData {
            return "No verdict yet. The engine is still collecting enough baseline evidence."
        }
        return "Engine verdict built from today's local readiness signals."
    }

    private static func topSignals(from readiness: DailyReadiness) -> [ReadinessSignalSummary] {
        var candidates = signalCandidates(from: readiness)
        let priority = signalPriority(for: readiness.ruleIDs)
        candidates.sort { lhs, rhs in
            let lhsPriority = priority[lhs.id] ?? Int.max
            let rhsPriority = priority[rhs.id] ?? Int.max
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.order < rhs.order
        }
        return Array(candidates.prefix(3).map(\.summary))
    }

    private static func signalPriority(for rules: [ReadinessRuleID]) -> [String: Int] {
        var priority: [String: Int] = [:]
        for (index, rule) in rules.enumerated() {
            let ids: [String]
            switch rule {
            case .hrvLow, .overreaching, .sourceDispute:
                ids = ["hrv"]
            case .rhrElevated:
                ids = ["rhr"]
            case .shortSleep:
                ids = ["sleep"]
            case .loadRamp:
                ids = ["load"]
            case .soreness, .illness, .persistenceHold, .overrideWidened:
                ids = []
            }
            for id in ids where priority[id] == nil {
                priority[id] = index
            }
        }
        return priority
    }

    private struct SignalCandidate {
        let order: Int
        let summary: ReadinessSignalSummary
        var id: String { summary.id }
    }

    private static func signalCandidates(from readiness: DailyReadiness) -> [SignalCandidate] {
        var candidates: [SignalCandidate] = []

        if let hrv = readiness.hrvMean7 {
            let baseline = readiness.hrvBaseline ?? readiness.hrvMean28
            let value = baseline.map {
                "7-day \(Int(hrv.rounded())) ms vs baseline \(Int($0.rounded())) ms"
            } ?? "7-day \(Int(hrv.rounded())) ms"
            candidates.append(.init(order: 0, summary: .init(id: "hrv", label: "HRV", value: value, symbol: "waveform.path.ecg")))
        }

        if let rhr = readiness.rhrMean7 {
            let baseline = readiness.rhrBaseline ?? readiness.rhrMean28
            let value = baseline.map {
                "7-day \(Int(rhr.rounded())) bpm vs baseline \(Int($0.rounded())) bpm"
            } ?? "7-day \(Int(rhr.rounded())) bpm"
            candidates.append(.init(order: 1, summary: .init(id: "rhr", label: "Resting HR", value: value, symbol: "heart")))
        }

        if let sleep = readiness.sleepLastNight {
            let value = readiness.sleepMean14.map {
                "\(Formatters.sleep(sleep)) last night vs \(Formatters.sleep($0)) 14-day mean"
            } ?? "\(Formatters.sleep(sleep)) last night"
            candidates.append(.init(order: 2, summary: .init(id: "sleep", label: "Sleep", value: value, symbol: "bed.double")))
        }

        if let load = readiness.acuteChronicRatio {
            let value = String(format: "%.2f acute:chronic load", load)
            candidates.append(.init(order: 3, summary: .init(id: "load", label: "Load", value: value, symbol: "chart.line.uptrend.xyaxis")))
        }

        if candidates.isEmpty, let score = readiness.score {
            candidates.append(.init(order: 4, summary: .init(id: "score", label: "Readiness", value: "\(score)/100", symbol: "gauge.with.needle")))
        }

        return candidates
    }
}

struct ReadinessSignalSummary: Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
    var symbol: String
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
