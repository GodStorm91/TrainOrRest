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
        failureMessage: String
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
    }
}

@MainActor
final class WorkoutReplacementCoordinator: ObservableObject {
    @Published private(set) var pending: PendingWorkoutReplacement?
    @Published private(set) var isConfirming = false
    @Published private(set) var lastError: String?

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

    func stage(_ replacement: PendingWorkoutReplacement) {
        guard pending == nil, !isConfirming else { return }
        pending = replacement
        lastError = nil
    }

    func cancel() {
        guard !isConfirming else { return }
        pending = nil
        lastError = nil
    }

    func confirm(_ id: UUID) {
        guard let replacement = pending, replacement.id == id, !isConfirming else { return }

        pending = nil
        isConfirming = true
        defer { isConfirming = false }

        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            try CoachTools.confirmReplacement(
                replacement,
                in: context,
                today: now(),
                calendar: calendar
            )
            NotificationCenter.default.post(name: .planDidChange, object: nil)
        } catch {
            lastError = replacement.failureMessage
        }
    }
}
