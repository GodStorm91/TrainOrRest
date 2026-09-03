import Foundation
import SwiftData

struct WorkoutReplacementSummary: Equatable {
    let kind: WorkoutKind
    let distanceKm: Double
}

struct WorkoutReplacementPresentation: Equatable {
    let title: String
    let message: String
    let replaceAction: String
    let keepAction: String
}

struct WorkoutReplacementFingerprint: Equatable {
    let uuid: UUID
    let date: Date
    let weekIndex: Int
    let phaseRaw: String
    let kindRaw: String
    let distanceKm: Double
    let paceFastSecPerKm: Double?
    let paceSlowSecPerKm: Double?
    let details: String
    let structure: [WorkoutStepGroup]
    let statusRaw: String
    let manuallyOverridden: Bool
    let matchedActivityUUID: UUID?

    init(workout: PlannedWorkout) {
        uuid = workout.uuid
        date = workout.date
        weekIndex = workout.weekIndex
        phaseRaw = workout.phaseRaw
        kindRaw = workout.kindRaw
        distanceKm = workout.distanceKm
        paceFastSecPerKm = workout.paceFastSecondsPerKm
        paceSlowSecPerKm = workout.paceSlowSecondsPerKm
        details = workout.details
        structure = workout.structure
        statusRaw = workout.statusRaw
        manuallyOverridden = workout.manuallyOverridden
        matchedActivityUUID = workout.matchedActivityUUID
    }

    func matches(_ workout: PlannedWorkout) -> Bool {
        self == WorkoutReplacementFingerprint(workout: workout)
    }
}

struct PendingWorkoutReplacement: Identifiable, Equatable {
    let id: UUID
    let expected: WorkoutReplacementFingerprint
    let date: Date
    let payload: PlanAdjustmentProposal.CreateWorkout
    let presentation: WorkoutReplacementPresentation
    /// What the day holds now, and what would take its place — rendered as the
    /// before/after rows of the plan-update card.
    let existing: WorkoutReplacementSummary
    let proposed: WorkoutReplacementSummary
    /// Change to the affected week's target volume, in km. This is the same
    /// delta the plan engine applies; nothing here is estimated.
    let volumeDeltaKm: Double
    let appliedSummary: String
    let successMessage: String
    let failureMessage: String
    let planChangedSinceProposed: Bool

    init(
        expected: WorkoutReplacementFingerprint,
        date: Date,
        payload: PlanAdjustmentProposal.CreateWorkout,
        presentation: WorkoutReplacementPresentation,
        existing: WorkoutReplacementSummary,
        proposed: WorkoutReplacementSummary,
        volumeDeltaKm: Double,
        appliedSummary: String,
        successMessage: String,
        failureMessage: String,
        planChangedSinceProposed: Bool = false
    ) {
        id = UUID()
        self.expected = expected
        self.date = date
        self.payload = payload
        self.presentation = presentation
        self.existing = existing
        self.proposed = proposed
        self.volumeDeltaKm = volumeDeltaKm
        self.appliedSummary = appliedSummary
        self.successMessage = successMessage
        self.failureMessage = failureMessage
        self.planChangedSinceProposed = planChangedSinceProposed
    }

    func withPlanChangedSinceProposed(_ changed: Bool) -> PendingWorkoutReplacement {
        PendingWorkoutReplacement(
            expected: expected,
            date: date,
            payload: payload,
            presentation: presentation,
            existing: existing,
            proposed: proposed,
            volumeDeltaKm: volumeDeltaKm,
            appliedSummary: appliedSummary,
            successMessage: successMessage,
            failureMessage: failureMessage,
            planChangedSinceProposed: changed
        )
    }
}

struct PendingPlanProposal: Identifiable, Equatable {
    let id: UUID
    let proposal: PlanAdjustmentProposal
    let summary: String
    let threadID: UUID?

    init(proposal: PlanAdjustmentProposal, summary: String, threadID: UUID?) {
        self.id = UUID()
        self.proposal = proposal
        self.summary = summary
        self.threadID = threadID
    }
}

@MainActor
final class WorkoutReplacementCoordinator: ObservableObject {
    @Published private(set) var pending: PendingWorkoutReplacement?
    @Published private(set) var pendingProposal: PendingPlanProposal?
    @Published private(set) var isConfirming = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastConfirmationKind: ConfirmationKind?

    enum ConfirmationKind: Equatable {
        case required
        case notRequired
    }

    static func confirmationKind(for proposal: PlanAdjustmentProposal) -> ConfirmationKind {
        let restCount = proposal.changes.filter { $0.action == .rest }.count
        if restCount > 1 { return .required }
        if proposal.changes.count == 1,
           let action = proposal.changes.first?.action,
           action == .create || action == .replace {
            return .notRequired
        }
        return .required
    }

    private let container: ModelContainer
    private let calendar: Calendar
    private let now: () -> Date

    init(
        container: ModelContainer,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.container = container
        self.calendar = calendar
        self.now = now
    }

    var hasPendingDecision: Bool {
        pending != nil || pendingProposal != nil
    }

    func stage(_ replacement: PendingWorkoutReplacement) {
        guard !hasPendingDecision, !isConfirming else { return }
        pending = replacement
        lastError = nil
        lastConfirmationKind = .notRequired
    }

    func stage(_ proposal: PlanAdjustmentProposal, summary: String, threadID: UUID?) {
        guard !hasPendingDecision, !isConfirming else { return }
        pendingProposal = PendingPlanProposal(proposal: proposal, summary: summary, threadID: threadID)
        lastError = nil
        lastConfirmationKind = .required
    }

    func cancel() {
        guard !isConfirming else { return }
        pending = nil
        pendingProposal = nil
        lastError = nil
        lastConfirmationKind = nil
    }

    func confirm(_ id: UUID) {
        guard let replacement = pending, replacement.id == id, !isConfirming else { return }

        pending = nil
        isConfirming = true
        defer { isConfirming = false }

        do {
            let context = container.mainContext
            context.autosaveEnabled = false
            try CoachTools.confirmReplacement(
                replacement,
                in: context,
                today: now(),
                calendar: calendar
            )
            NotificationCenter.default.post(name: .planDidChange, object: nil)
        } catch CoachTools.ReplacementError.staleTarget {
            restageChangedPlanReplacement(from: replacement)
        } catch {
            lastError = replacement.failureMessage
        }
    }

    func confirmProposal(_ id: UUID) {
        guard let pendingProposal, pendingProposal.id == id, !isConfirming else { return }

        self.pendingProposal = nil
        isConfirming = true
        defer { isConfirming = false }

        do {
            let context = container.mainContext
            context.autosaveEnabled = false
            let result = try CoachTools.apply(
                proposal: pendingProposal.proposal,
                in: context,
                today: now(),
                calendar: calendar
            )
            context.insert(ChatMessage(
                role: .assistant,
                text: "Applied: \(result.summary)",
                date: .now,
                appliedAdjustment: result.summary,
                threadID: pendingProposal.threadID
            ))
            try context.save()
            NotificationCenter.default.post(name: .planDidChange, object: nil)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func restageChangedPlanReplacement(from replacement: PendingWorkoutReplacement) {
        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let proposal = PlanAdjustmentProposal(changes: [.init(
                date: CoachContextBuilder.day(replacement.date, calendar: calendar),
                action: .create,
                detail: nil,
                workout: replacement.payload
            )])
            guard let fresh = try CoachTools.pendingReplacement(
                for: proposal,
                in: context,
                today: now(),
                calendar: calendar,
                language: .en
            ) else {
                lastError = "That day is no longer available — ask the coach again."
                return
            }
            pending = fresh.withPlanChangedSinceProposed(true)
            lastError = nil
        } catch {
            lastError = "That day is no longer available — ask the coach again."
        }
    }
}
