import Foundation
import SwiftData

struct NewRun: Equatable {
    let hkUUID: UUID
    let endDate: Date
}

enum AdaptivePlanReviewOrigin: String, Codable {
    case automatic
    case manual
}

enum AdaptivePlanReviewPhase: String, Codable, CaseIterable {
    case queued
    case needsKey
    case preparing
    case proposal
    case noChange
    case failed
    case stale
    case applied
    case reverted
    case superseded
    case dismissed
}

enum AdaptivePlanReviewAttemptKind: String, Codable {
    case automatic
    case manual
}

enum AdaptivePlanReviewAction {
    case apply(acknowledging: [PlanValidator.Issue])
    case dismiss
    case retry
}

enum AdaptivePlanReviewSettings {
    static let automaticKey = "adaptiveNextWeekReviewAutomatic"
}

@Model
final class AdaptivePlanReview {
    var id: UUID
    @Attribute(.unique) var triggerKey: String
    var originRaw: String
    var triggerActivityUUID: UUID?
    var phaseRaw: String
    var createdAt: Date
    var updatedAt: Date
    var resolvedAt: Date?
    var supersededByID: UUID?
    var lastError: String?
    var requestedWindowStart: Date
    var requestedWindowEnd: Date
    var scopeRaw: String
    var basePlanRevision: String?
    var proposalJSON: String?
    var summary: String?
    var candidateID: UUID?
    var planEditID: UUID?
    var autoAttemptedAt: Date?
    var activeAttemptToken: UUID?
    var latestAttemptKindRaw: String?
    var manualRetryCount: Int

    init(
        id: UUID = UUID(),
        triggerKey: String,
        origin: AdaptivePlanReviewOrigin,
        triggerActivityUUID: UUID?,
        window: NextSevenDayWindow,
        createdAt: Date
    ) {
        self.id = id
        self.triggerKey = triggerKey
        self.originRaw = origin.rawValue
        self.triggerActivityUUID = triggerActivityUUID
        self.phaseRaw = AdaptivePlanReviewPhase.queued.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.resolvedAt = nil
        self.supersededByID = nil
        self.lastError = nil
        self.requestedWindowStart = window.start
        self.requestedWindowEnd = window.end
        self.scopeRaw = "adaptiveNextWeek"
        self.basePlanRevision = nil
        self.proposalJSON = nil
        self.summary = nil
        self.candidateID = nil
        self.planEditID = nil
        self.autoAttemptedAt = nil
        self.activeAttemptToken = nil
        self.latestAttemptKindRaw = nil
        self.manualRetryCount = 0
    }

    var origin: AdaptivePlanReviewOrigin {
        AdaptivePlanReviewOrigin(rawValue: originRaw) ?? .manual
    }

    var phase: AdaptivePlanReviewPhase {
        AdaptivePlanReviewPhase(rawValue: phaseRaw) ?? .failed
    }

    var latestAttemptKind: AdaptivePlanReviewAttemptKind? {
        latestAttemptKindRaw.flatMap(AdaptivePlanReviewAttemptKind.init(rawValue:))
    }

    var scope: PlanEditScope {
        .adaptiveNextWeek(NextSevenDayWindow(start: requestedWindowStart, end: requestedWindowEnd))
    }

    func transition(to phase: AdaptivePlanReviewPhase, at date: Date, error: String? = nil) {
        phaseRaw = phase.rawValue
        updatedAt = date
        lastError = error
        if phase.isTerminal {
            resolvedAt = date
        }
    }
}

extension AdaptivePlanReviewPhase {
    var isTerminal: Bool {
        switch self {
        case .noChange, .applied, .reverted, .superseded, .dismissed:
            true
        case .queued, .needsKey, .preparing, .proposal, .failed, .stale:
            false
        }
    }

    var canBeSuperseded: Bool {
        switch self {
        case .queued, .needsKey, .preparing, .proposal, .noChange, .failed:
            true
        case .stale, .applied, .reverted, .superseded, .dismissed:
            false
        }
    }
}

struct AdaptiveReviewProposalResponse: Codable, Equatable {
    enum Outcome: String, Codable {
        case proposal
        case noChanges = "no_changes"
    }

    var outcome: Outcome
    var summary: String
    var changes: [PlanAdjustmentProposal.Change]
}

@MainActor
enum AdaptiveReviewTool {
    static let name = "propose_next_week_review"

    static var tool: ClaudeTool {
        ClaudeTool(
            name: name,
            description: "Return one safe review for the next seven local days. Use no_changes with an empty changes array when no plan edit is needed. Never suggest changes outside the supplied window.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "outcome": .object([
                        "type": .string("string"),
                        "enum": .array([.string("proposal"), .string("no_changes")])
                    ]),
                    "summary": .object(["type": .string("string")]),
                    "changes": .object([
                        "type": .string("array"),
                        "minItems": .number(0),
                        "maxItems": .number(5),
                        "items": PlanProposalSchema.changeSchema
                    ])
                ]),
                "required": .array([.string("outcome"), .string("summary"), .string("changes")])
            ])
        )
    }
}
