import CryptoKit
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

struct NextSevenDayWindow: Codable, Equatable {
    let start: Date
    let end: Date
}

enum PlanEditScope: Codable, Equatable {
    case standard
    case adaptiveNextWeek(NextSevenDayWindow)
}



struct CoachPlanCandidate: Identifiable {
    enum Presentation {
        case replacement(
            date: Date,
            existing: WorkoutReplacementSummary,
            proposed: WorkoutReplacementSummary,
            copy: WorkoutReplacementPresentation,
            volumeDeltaKm: Double
        )
        case proposal
    }

    let id: UUID
    let proposal: PlanAdjustmentProposal
    let baseRevision: String
    let transaction: PlanEditTransaction
    let summary: String
    /// Every issue attached to this edit. `loadRisks` need an explicit
    /// acknowledgement before commit; `notes` are informational only.
    let warnings: [PlanValidator.Issue]
    let presentation: Presentation
    let threadID: UUID?
    let scope: PlanEditScope
    let changedSinceProposed: Bool

    var primaryDate: Date? {
        transaction.operations.lazy.compactMap { $0.after?.date ?? $0.before?.date }.first
    }

    var loadRisks: [PlanValidator.Issue] { warnings.filter { $0.kind.severity == .acknowledge } }
    var notes: [PlanValidator.Issue] { warnings.filter { $0.kind.severity == .inform } }

}

struct CoachPlanReceipt: Equatable {
    let id: UUID
    let summary: String
    let appliedAt: Date
    let primaryDate: Date?
}

enum CoachPlanCommitResult {
    case applied(CoachPlanReceipt)
    case stale(CoachPlanCandidate)
}

@MainActor
enum CoachPlanRevision {
    private struct State: Codable {
        var generatedAt: Date
        var anchorDate: Date
        var weekPhasesRaw: [String]
        var weekTargetVolumesKm: [Double]
        var weekIsDown: [Bool]
        var pausedAt: Date?
        var workouts: [PlanWorkoutReceiptSnapshot]
    }

    static func current(in context: ModelContext) throws -> String {
        guard let plan = try PlanStore.activePlan(in: context) else { return "none" }
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
            .filter { $0.plan === plan }
            .map(PlanWorkoutReceiptSnapshot.init)
            .sorted { $0.uuid.uuidString < $1.uuid.uuidString }
        let state = State(
            generatedAt: plan.generatedAt,
            anchorDate: plan.anchorDate,
            weekPhasesRaw: plan.weekPhasesRaw,
            weekTargetVolumesKm: plan.weekTargetVolumesKm,
            weekIsDown: plan.weekIsDown,
            pausedAt: plan.pausedAt,
            workouts: workouts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
enum CoachPlanCandidateEngine {
    private struct Workspace {
        var baseline: TrainingPlanSpec
        var candidate: TrainingPlanSpec
        var snapshots: [UUID: PlanWorkoutReceiptSnapshot]
        var identityByDay: [Date: UUID]
        /// Extra rows left on a day by the old clone bug. Editing that day
        /// keeps the preferred row and deletes the rest in the same transaction.
        var duplicatesByDay: [Date: [UUID]]
        var original: [UUID: PlanWorkoutReceiptSnapshot]
        var summaries: [String] = []
        var notes: [PlanValidator.Issue] = []
        let language: CoachLanguage

        /// Quality work built without recent-run data ships unpaced. That is
        /// information for the runner, never a reason to refuse the edit.
        mutating func noteIfUnpaced(_ built: BuiltWorkout, paces: TrainingPaces?) {
            guard paces == nil else { return }
            switch built.kind {
            case .tempo, .threshold, .intervals:
                notes.append(PlanValidator.Issue(kind: .paceUnavailable, weekIndex: nil, message: language.paceUnavailableNote(kind: built.kind)))
            case .easy, .long, .race:
                break
            }
        }
    }

    static func prepare(
        proposal: PlanAdjustmentProposal,
        scope: PlanEditScope,
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        language: CoachLanguage,
        threadID: UUID? = nil,
        changedSinceProposed: Bool = false
    ) throws -> CoachPlanCandidate {
        guard !proposal.changes.isEmpty else { throw CoachTools.ValidationError("No changes proposed.") }
        guard proposal.changes.count <= CoachTools.maxChangesPerProposal else {
            throw CoachTools.ValidationError("At most \(CoachTools.maxChangesPerProposal) changes per proposal.")
        }
        for change in proposal.changes { try validateFields(change) }

        guard let goal = try PlanStore.activeGoal(in: context)?.spec,
              let plan = try PlanStore.activePlan(in: context) else {
            throw CoachTools.ValidationError("No active plan.")
        }
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }
        let baseline = try currentPlanSpec(plan: plan, goal: goal, in: context, today: today, calendar: calendar)
        let rows = try context.fetch(FetchDescriptor<PlannedWorkout>()).filter { $0.plan === plan }
        try validate(scope: scope, proposal: proposal, rows: rows, goal: goal, today: today, calendar: calendar)
        let original = Dictionary(uniqueKeysWithValues: rows.map {
            let snapshot = PlanWorkoutReceiptSnapshot(workout: $0)
            return (snapshot.uuid, snapshot)
        })
        var identityByDay: [Date: UUID] = [:]
        var duplicatesByDay: [Date: [UUID]] = [:]
        for (day, group) in Dictionary(grouping: rows, by: { calendar.startOfDay(for: $0.date) }) {
            guard let keeper = PlannedWorkout.preferredAmongDuplicates(group) else { continue }
            identityByDay[day] = keeper.uuid
            let extras = group.map(\.uuid).filter { $0 != keeper.uuid }
            if !extras.isEmpty { duplicatesByDay[day] = extras }
        }
        var workspace = Workspace(
            baseline: baseline,
            candidate: baseline,
            snapshots: original,
            identityByDay: identityByDay,
            duplicatesByDay: duplicatesByDay,
            original: original,
            language: language
        )

        let changes = proposal.changes

        let dayStart = calendar.startOfDay(for: today)
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        var editedDates: Set<Date> = []
        for change in changes where change.action != .create {
            let date = try CoachTools.parseDay(change.date, calendar: calendar)
            guard date >= dayStart else { throw CoachTools.ValidationError("Cannot edit past workouts.") }
            editedDates.insert(date)
            try applyExisting(
                change,
                date: date,
                paces: paces,
                to: &workspace,
                calendar: calendar
            )
        }

        var proposedCreateDates: Set<Date> = []
        for change in changes where change.action == .create {
            let date = try CoachTools.parseDay(change.date, calendar: calendar)
            guard date >= dayStart else { throw CoachTools.ValidationError("Cannot create a workout in the past.") }
            guard !editedDates.contains(date) else {
                throw CoachTools.ValidationError("Create the replacement workout on a different date, or ask to replace the workout explicitly.")
            }
            guard date != raceDay else { throw CoachTools.ValidationError("Race day cannot hold another workout.") }
            guard date < raceDay else { throw CoachTools.ValidationError("\(change.date) is after race day.") }
            guard proposedCreateDates.insert(date).inserted else {
                throw CoachTools.ValidationError("Two workouts proposed for \(change.date).")
            }
            guard workspace.identityByDay[date] == nil else {
                throw CoachTools.ValidationError("\(change.date) already has a workout.")
            }
            guard let weekIndex = weekIndex(for: date, in: workspace.candidate, calendar: calendar) else {
                throw CoachTools.ValidationError("\(change.date) is outside the training plan.")
            }
            guard let payload = change.workout else { throw CoachTools.ValidationError("create requires a workout.") }
            let built = try WorkoutFactory.build(try recipe(from: payload), paces: paces)
            workspace.noteIfUnpaced(built, paces: paces)
            let phase = workspace.candidate.weeks[weekIndex].phase
            var week = workspace.candidate.weeks[weekIndex]
            week.workouts.append(spec(date: date, built: built))
            week.workouts.sort { $0.date < $1.date }
            week.targetVolumeKm = PlanGenerator.rounded(week.targetVolumeKm + built.distanceKm)
            workspace.candidate.weeks[weekIndex] = week
            let snapshot = newSnapshot(date: date, weekIndex: weekIndex, phase: phase, built: built)
            workspace.snapshots[snapshot.uuid] = snapshot
            workspace.identityByDay[date] = snapshot.uuid
            workspace.summaries.append("Created \(built.kind.rawValue) on \(change.date)")
        }

        let peakCap = fitness.map { max($0.weeklyVolumeKm * 1.35, $0.longestRecentRunKm * 2) }
        let issues = introducedValidationIssues(
            in: workspace.candidate,
            comparedTo: workspace.baseline,
            calendar: calendar,
            peakCapKm: peakCap
        )
        let warnings = try warningsForConfirmation(from: issues) + workspace.notes
        let transaction = try PlanEditReceiptCodec.canonicalized(transaction(from: workspace))
        guard !transaction.operations.isEmpty || !transaction.weekTargets.isEmpty else {
            throw CoachTools.ValidationError("No change to apply; the proposed plan matches the current one.")
        }
        let summary = workspace.summaries.joined(separator: "; ")
        let presentation = replacementPresentation(
            changes: changes,
            transaction: transaction,
            language: language
        )
        return CoachPlanCandidate(
            id: UUID(),
            proposal: proposal,
            baseRevision: try CoachPlanRevision.current(in: context),
            transaction: transaction,
            summary: summary,
            warnings: warnings,
            presentation: presentation,
            threadID: threadID,
            scope: scope,
            changedSinceProposed: changedSinceProposed
        )
    }

    static func commit(
        _ candidate: CoachPlanCandidate,
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        language: CoachLanguage,
        acknowledging warnings: [PlanValidator.Issue] = [],
        beforeSave: ((CoachPlanReceipt) throws -> Void)? = nil
    ) throws -> CoachPlanCommitResult {
        if try CoachPlanRevision.current(in: context) != candidate.baseRevision {
            let fresh = try prepare(
                proposal: candidate.proposal,
                scope: candidate.scope,
                in: context,
                today: today,
                calendar: calendar,
                language: language,
                threadID: candidate.threadID,
                changedSinceProposed: true
            )
            return .stale(fresh)
        }
        let acknowledged = warnings.filter { $0.kind.severity == .acknowledge }
        let remaining = candidate.loadRisks.filter { !acknowledged.contains($0) }
        guard remaining.isEmpty else {
            throw CoachTools.ValidationError(remaining.map(\.message).joined(separator: "; "))
        }

        guard let plan = try PlanStore.activePlan(in: context) else {
            throw CoachTools.ValidationError("The active plan is no longer available.")
        }
        let rows = try context.fetch(FetchDescriptor<PlannedWorkout>())
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.uuid, $0) })
        for operation in candidate.transaction.operations {
            if let before = operation.before {
                guard let current = byID[before.uuid],
                      PlanEditReceiptCodec.snapshotsMatch(
                        PlanWorkoutReceiptSnapshot(workout: current),
                        before
                      ) else {
                    return .stale(try prepare(
                        proposal: candidate.proposal,
                        scope: candidate.scope,
                        in: context,
                        today: today,
                        calendar: calendar,
                        language: language,
                        threadID: candidate.threadID,
                        changedSinceProposed: true
                    ))
                }
            } else if let after = operation.after, byID[after.uuid] != nil {
                return .stale(try prepare(
                    proposal: candidate.proposal,
                    scope: candidate.scope,
                    in: context,
                    today: today,
                    calendar: calendar,
                    language: language,
                    threadID: candidate.threadID,
                    changedSinceProposed: true
                ))
            }
        }

        try validate(
            scope: candidate.scope,
            transaction: candidate.transaction,
            rowsByID: byID,
            goal: try PlanStore.activeGoal(in: context)?.spec,
            today: today,
            calendar: calendar
        )
        let operationData = try PlanEditReceiptCodec.encode(candidate.transaction)
        let transaction = try PlanEditReceiptCodec.decode(operationData)
        let edit = PlanEdit(
            appliedAt: today,
            transaction: transaction,
            operationData: operationData,
            summary: candidate.summary,
            basePlanRevision: candidate.baseRevision
        )
        let receipt = CoachPlanReceipt(
            id: edit.id,
            summary: candidate.summary,
            appliedAt: today,
            primaryDate: candidate.primaryDate
        )

        do {
            context.insert(edit)
            for operation in transaction.operations {
                switch (operation.before, operation.after) {
                case (.some(let before), nil):
                    guard let row = byID[before.uuid] else { throw CoachTools.ReplacementError.staleTarget }
                    context.delete(row)
                case (nil, .some(let after)):
                    context.insert(after.makeWorkout(plan: plan))
                case (.some(let before), .some(let after)):
                    guard let row = byID[before.uuid] else { throw CoachTools.ReplacementError.staleTarget }
                    after.apply(to: row)
                    row.plan = plan
                case (nil, nil):
                    break
                }
            }
            var targets = plan.weekTargetVolumesKm
            for target in transaction.weekTargets {
                guard targets.indices.contains(target.weekIndex) else {
                    throw CoachTools.ValidationError("Plan week \(target.weekIndex) is missing.")
                }
                targets[target.weekIndex] = target.after
            }
            plan.weekTargetVolumesKm = targets
            plan.generatedAt = today
            edit.appliedPlanRevision = try CoachPlanRevision.current(in: context)
            try beforeSave?(receipt)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        NotificationCenter.default.post(name: .planDidChange, object: nil)
        return .applied(receipt)
    }

    private static func validate(
        scope: PlanEditScope,
        proposal: PlanAdjustmentProposal,
        rows: [PlannedWorkout],
        goal: GoalSpec,
        today: Date,
        calendar: Calendar
    ) throws {
        guard case let .adaptiveNextWeek(window) = scope else { return }
        let allowed = try adaptiveWindow(window, today: today, calendar: calendar)
        let rowsByDay = Dictionary(grouping: rows, by: { calendar.startOfDay(for: $0.date) })

        for change in proposal.changes {
            let source = try CoachTools.parseDay(change.date, calendar: calendar)
            try requireAllowed(source, in: allowed)
            try requireNotRaceDay(source, goal: goal, calendar: calendar)
            if change.action != .create {
                let row = try plannedRow(on: source, in: rowsByDay)
                try validateExisting(row, on: source, goal: goal, calendar: calendar)
            }

            switch change.action {
            case .move:
                let target = try targetDay(change.detail, calendar: calendar)
                try requireAllowed(target, in: allowed)
                try requireNotRaceDay(target, goal: goal, calendar: calendar)
            case .swap:
                let target = try targetDay(change.detail, calendar: calendar)
                try requireAllowed(target, in: allowed)
                let row = try plannedRow(on: target, in: rowsByDay)
                try validateExisting(row, on: target, goal: goal, calendar: calendar)
            case .create, .replace, .rest, .downgrade:
                break
            }
        }
    }

    private static func validate(
        scope: PlanEditScope,
        transaction: PlanEditTransaction,
        rowsByID: [UUID: PlannedWorkout],
        goal: GoalSpec?,
        today: Date,
        calendar: Calendar
    ) throws {
        guard case let .adaptiveNextWeek(window) = scope else { return }
        guard let goal else {
            throw CoachTools.ValidationError("The active goal is no longer available.")
        }
        let allowed = try adaptiveWindow(window, today: today, calendar: calendar)
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        for operation in transaction.operations {
            for snapshot in [operation.before, operation.after].compactMap({ $0 }) {
                try requireAllowed(calendar.startOfDay(for: snapshot.date), in: allowed)
                guard calendar.startOfDay(for: snapshot.date) != raceDay,
                      snapshot.kindRaw != WorkoutKind.race.rawValue else {
                    throw CoachTools.ValidationError("Race day cannot be edited.")
                }
            }
            if let before = operation.before {
                guard let row = rowsByID[before.uuid],
                      row.status == .planned else {
                    throw CoachTools.ValidationError("Only planned workouts can be reviewed.")
                }
                guard !row.isScheduleLocked else {
                    throw CoachTools.ValidationError("Locked workouts cannot be reviewed.")
                }
            }
        }
    }

    private static func adaptiveWindow(
        _ stored: NextSevenDayWindow,
        today: Date,
        calendar: Calendar
    ) throws -> NextSevenDayWindow {
        let liveStart = calendar.startOfDay(for: today)
        guard let liveEnd = calendar.date(byAdding: .day, value: 7, to: liveStart) else {
            throw CoachTools.ValidationError("Could not calculate the review window.")
        }
        let start = max(stored.start, liveStart)
        let end = min(stored.end, liveEnd)
        guard start < end else {
            throw CoachTools.ValidationError("The review window is no longer available.")
        }
        return NextSevenDayWindow(start: start, end: end)
    }

    private static func requireAllowed(_ date: Date, in window: NextSevenDayWindow) throws {
        guard date >= window.start, date < window.end else {
            throw CoachTools.ValidationError("All next-week review changes must stay within the active seven-day window.")
        }
    }

    private static func requireNotRaceDay(
        _ date: Date,
        goal: GoalSpec,
        calendar: Calendar
    ) throws {
        guard calendar.startOfDay(for: date) != calendar.startOfDay(for: goal.raceDate) else {
            throw CoachTools.ValidationError("Race day cannot be edited.")
        }
    }

    private static func plannedRow(
        on day: Date,
        in rowsByDay: [Date: [PlannedWorkout]]
    ) throws -> PlannedWorkout {
        guard let row = rowsByDay[day].flatMap(PlannedWorkout.preferredAmongDuplicates) else {
            throw CoachTools.ValidationError("No planned workout exists on the requested day.")
        }
        return row
    }

    private static func validateExisting(
        _ row: PlannedWorkout,
        on day: Date,
        goal: GoalSpec,
        calendar: Calendar
    ) throws {
        guard row.status == .planned else {
            throw CoachTools.ValidationError("Only planned workouts can be reviewed.")
        }
        guard !row.isScheduleLocked else {
            throw CoachTools.ValidationError("Locked workouts cannot be reviewed.")
        }
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        guard day != raceDay, row.kind != .race else {
            throw CoachTools.ValidationError("Race day cannot be edited.")
        }
    }

    private static func applyExisting(
        _ change: PlanAdjustmentProposal.Change,
        date: Date,
        paces: TrainingPaces?,
        to workspace: inout Workspace,
        calendar: Calendar
    ) throws {
        if let extras = workspace.duplicatesByDay.removeValue(forKey: date) {
            for extra in extras { workspace.snapshots.removeValue(forKey: extra) }
            workspace.summaries.append("Removed \(extras.count) duplicate workout(s) on \(change.date)")
        }
        guard let location = locate(date, in: workspace.candidate, calendar: calendar),
              let identity = workspace.identityByDay[date],
              var snapshot = workspace.snapshots[identity] else {
            throw CoachTools.ValidationError("No workout on \(change.date). For move, set date to the source day that already has the workout and detail to the empty target day. To add a new workout on this date, use create with a workout payload.")
        }
        guard snapshot.kindRaw != WorkoutKind.race.rawValue else {
            throw CoachTools.ValidationError("Race day cannot be edited.")
        }
        let workout = workspace.candidate.weeks[location.week].workouts[location.workout]

        switch change.action {
        case .create:
            preconditionFailure("create is handled after existing edits")
        case .rest:
            workspace.candidate.weeks[location.week].workouts.remove(at: location.workout)
            workspace.snapshots.removeValue(forKey: identity)
            workspace.identityByDay.removeValue(forKey: date)
            workspace.summaries.append("Rested \(change.date)")
        case .downgrade:
            let built = WorkoutFactory.canonicalEasy(distanceKm: workout.distanceKm, paces: paces)
            workspace.candidate.weeks[location.week].workouts[location.workout] = spec(date: date, built: built)
            applyBuilt(built, to: &snapshot, resetCompletion: false)
            snapshot.manuallyOverridden = true
            workspace.snapshots[identity] = snapshot
            workspace.summaries.append("Downgraded \(change.date) to easy")
        case .move:
            let target = try targetDay(change.detail, calendar: calendar)
            guard workspace.identityByDay[target] == nil else {
                throw CoachTools.ValidationError("Target date already has a workout.")
            }
            guard let targetWeek = weekIndex(for: target, in: workspace.candidate, calendar: calendar) else {
                throw CoachTools.ValidationError("\(CoachContextBuilder.day(target, calendar: calendar)) is outside the training plan.")
            }
            workspace.candidate.weeks[location.week].workouts.remove(at: location.workout)
            if targetWeek != location.week {
                workspace.candidate.weeks[location.week].targetVolumeKm = PlanGenerator.rounded(
                    workspace.candidate.weeks[location.week].targetVolumeKm - workout.distanceKm
                )
                workspace.candidate.weeks[targetWeek].targetVolumeKm = PlanGenerator.rounded(
                    workspace.candidate.weeks[targetWeek].targetVolumeKm + workout.distanceKm
                )
            }
            var moved = workout
            moved.date = target
            workspace.candidate.weeks[targetWeek].workouts.append(moved)
            workspace.candidate.weeks[targetWeek].workouts.sort { $0.date < $1.date }
            workspace.identityByDay.removeValue(forKey: date)
            workspace.identityByDay[target] = identity
            snapshot.date = target
            snapshot.weekIndex = targetWeek
            snapshot.phaseRaw = workspace.candidate.weeks[targetWeek].phase.rawValue
            snapshot.manuallyOverridden = true
            workspace.snapshots[identity] = snapshot
            workspace.summaries.append("Moved \(change.date) to \(CoachContextBuilder.day(target, calendar: calendar))")
        case .swap:
            let target = try targetDay(change.detail, calendar: calendar)
            guard let otherLocation = locate(target, in: workspace.candidate, calendar: calendar),
                  let otherID = workspace.identityByDay[target],
                  var otherSnapshot = workspace.snapshots[otherID] else {
                throw CoachTools.ValidationError("No workout on target date.")
            }
            workspace.candidate.weeks[location.week].workouts[location.workout].date = target
            workspace.candidate.weeks[otherLocation.week].workouts[otherLocation.workout].date = date
            snapshot.date = target
            snapshot.weekIndex = otherLocation.week
            snapshot.phaseRaw = workspace.candidate.weeks[otherLocation.week].phase.rawValue
            snapshot.manuallyOverridden = true
            otherSnapshot.date = date
            otherSnapshot.weekIndex = location.week
            otherSnapshot.phaseRaw = workspace.candidate.weeks[location.week].phase.rawValue
            otherSnapshot.manuallyOverridden = true
            workspace.snapshots[identity] = snapshot
            workspace.snapshots[otherID] = otherSnapshot
            workspace.identityByDay[date] = otherID
            workspace.identityByDay[target] = identity
            workspace.summaries.append("Swapped \(change.date) with \(CoachContextBuilder.day(target, calendar: calendar))")
        case .replace:
            guard let payload = change.workout else {
                throw CoachTools.ValidationError("replace requires a workout.")
            }
            let built = try WorkoutFactory.build(try recipe(from: payload), paces: paces)
            workspace.noteIfUnpaced(built, paces: paces)
            if workout.kind == built.kind,
               abs(workout.distanceKm - built.distanceKm) < 0.01,
               sameRecipe(workout.structure, built.structure) {
                throw CoachTools.ValidationError("No change to apply; the proposed workout matches the current one.")
            }
            workspace.candidate.weeks[location.week].workouts[location.workout] = spec(date: date, built: built)
            workspace.candidate.weeks[location.week].targetVolumeKm = PlanGenerator.rounded(
                workspace.candidate.weeks[location.week].targetVolumeKm + built.distanceKm - workout.distanceKm
            )
            applyBuilt(built, to: &snapshot, resetCompletion: true)
            snapshot.manuallyOverridden = true
            workspace.snapshots[identity] = snapshot
            workspace.summaries.append("Replaced \(change.date) with \(built.kind.rawValue)")
        }
    }

    private static func sameRecipe(_ lhs: [WorkoutStepGroup], _ rhs: [WorkoutStepGroup]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (leftGroup, rightGroup) in zip(lhs, rhs) {
            guard leftGroup.repeatCount == rightGroup.repeatCount,
                  leftGroup.steps.count == rightGroup.steps.count else {
                return false
            }
            for (leftStep, rightStep) in zip(leftGroup.steps, rightGroup.steps) {
                guard leftStep.role == rightStep.role,
                      optionalMeasure(leftStep.distanceKm, matches: rightStep.distanceKm),
                      optionalMeasure(leftStep.durationSeconds, matches: rightStep.durationSeconds) else {
                    return false
                }
            }
        }
        return true
    }

    private static func optionalMeasure(_ lhs: Double?, matches rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case let (.some(left), .some(right)): abs(left - right) < 0.01
        default: false
        }
    }

    private static func transaction(from workspace: Workspace) -> PlanEditTransaction {
        let identifiers = Set(workspace.original.keys).union(workspace.snapshots.keys)
        let operations = identifiers.compactMap { id -> PlanEditOperation? in
            let before = workspace.original[id]
            let after = workspace.snapshots[id]
            return before == after ? nil : PlanEditOperation(before: before, after: after)
        }.sorted {
            ($0.before?.uuid ?? $0.after!.uuid).uuidString < ($1.before?.uuid ?? $1.after!.uuid).uuidString
        }
        let weekTargets = workspace.baseline.weeks.indices.compactMap { index -> PlanEditWeekTarget? in
            let before = workspace.baseline.weeks[index].targetVolumeKm
            let after = workspace.candidate.weeks[index].targetVolumeKm
            guard before != after else { return nil }
            return PlanEditWeekTarget(weekIndex: index, before: before, after: after)
        }
        return PlanEditTransaction(operations: operations, weekTargets: weekTargets)
    }

    private static func replacementPresentation(
        changes: [PlanAdjustmentProposal.Change],
        transaction: PlanEditTransaction,
        language: CoachLanguage
    ) -> CoachPlanCandidate.Presentation {
        guard changes.count == 1,
              changes[0].action == .replace,
              transaction.operations.count == 1,
              let before = transaction.operations[0].before,
              let after = transaction.operations[0].after,
              let beforeKind = WorkoutKind(rawValue: before.kindRaw),
              let afterKind = WorkoutKind(rawValue: after.kindRaw) else {
            return .proposal
        }
        let existing = WorkoutReplacementSummary(kind: beforeKind, distanceKm: before.distanceKm)
        let proposed = WorkoutReplacementSummary(kind: afterKind, distanceKm: after.distanceKm)
        return .replacement(
            date: after.date,
            existing: existing,
            proposed: proposed,
            copy: language.replacementPresentation(date: after.date, existing: existing, proposed: proposed),
            volumeDeltaKm: PlanGenerator.rounded(after.distanceKm - before.distanceKm)
        )
    }

    private static func currentPlanSpec(
        plan: TrainingPlan,
        goal: GoalSpec,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> TrainingPlanSpec {
        let rows = try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))
            .filter { $0.plan === plan }
        // One row per day; leftover clones from the old persist path are represented by their preferred row.
        let workouts = Dictionary(grouping: rows, by: { calendar.startOfDay(for: $0.date) })
            .compactMap { PlannedWorkout.preferredAmongDuplicates($0.value) }
            .sorted { $0.date < $1.date }
        let weeks = plan.weekPhasesRaw.indices.map { index in
            let phase = TrainingPhase(rawValue: plan.weekPhasesRaw[index]) ?? .base
            let start = calendar.date(
                byAdding: .day,
                value: index * 7,
                to: PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
            )!
            let rows = workouts.filter { $0.weekIndex == index }.compactMap(toSpec)
            return WeekPlan(
                startDate: start,
                index: index,
                phase: phase,
                isDownWeek: plan.weekIsDown[index],
                isPartial: index == 0 && !calendar.isDate(plan.anchorDate, inSameDayAs: start),
                targetVolumeKm: plan.weekTargetVolumesKm[index],
                workouts: rows
            )
        }
        return TrainingPlanSpec(goal: goal, anchorDate: calendar.startOfDay(for: today), weeks: weeks)
    }

    private static func introducedValidationIssues(
        in candidate: TrainingPlanSpec,
        comparedTo baseline: TrainingPlanSpec,
        calendar: Calendar,
        peakCapKm: Double?
    ) -> [PlanValidator.Issue] {
        var remainingBaselineIssues = PlanValidator.validate(baseline, calendar: calendar, peakCapKm: peakCapKm)
        return PlanValidator.validate(candidate, calendar: calendar, peakCapKm: peakCapKm).compactMap { issue in
            guard issue.kind != .workoutOnUnavailableDay else { return nil }
            guard let match = remainingBaselineIssues.firstIndex(of: issue) else { return issue }
            remainingBaselineIssues.remove(at: match)
            return nil
        }
    }

    private static func warningsForConfirmation(from issues: [PlanValidator.Issue]) throws -> [PlanValidator.Issue] {
        let blocking = issues.filter { $0.kind.severity == .blocking }
        guard blocking.isEmpty else {
            throw CoachTools.ValidationError(blocking.map(\.message).joined(separator: "; "))
        }
        return issues
    }

    private static func validateFields(_ change: PlanAdjustmentProposal.Change) throws {
        switch change.action {
        case .create, .replace:
            guard change.workout != nil else {
                throw CoachTools.ValidationError("\(change.action.rawValue) requires a workout.")
            }
            guard change.detail == nil else {
                throw CoachTools.ValidationError("\(change.action.rawValue) does not take a detail date.")
            }
        case .move, .swap:
            guard change.detail != nil else {
                throw CoachTools.ValidationError("\(change.action.rawValue) requires a target date.")
            }
            guard change.workout == nil else {
                throw CoachTools.ValidationError("\(change.action.rawValue) does not take a workout.")
            }
        case .rest, .downgrade:
            guard change.detail == nil, change.workout == nil else {
                throw CoachTools.ValidationError("\(change.action.rawValue) takes only a date.")
            }
        }
    }

    private static func recipe(from payload: PlanAdjustmentProposal.CreateWorkout) throws -> WorkoutRecipe {
        guard let kind = WorkoutKind(rawValue: payload.kind) else {
            throw CoachTools.ValidationError("Unknown workout kind \(payload.kind).")
        }
        guard kind != .race else { throw CoachTools.ValidationError("Race workouts cannot be created.") }
        guard !payload.blocks.isEmpty, payload.blocks.count <= WorkoutFactory.Limits.maxBlocks else {
            throw CoachTools.ValidationError("A workout needs 1 to \(WorkoutFactory.Limits.maxBlocks) blocks.")
        }
        return WorkoutRecipe(kind: kind, blocks: try payload.blocks.map { block in
            guard !block.steps.isEmpty, block.steps.count <= WorkoutFactory.Limits.maxStepsPerBlock else {
                throw CoachTools.ValidationError("A block needs 1 to \(WorkoutFactory.Limits.maxStepsPerBlock) steps.")
            }
            return WorkoutRecipe.Block(repeatCount: block.repeatCount, steps: try block.steps.map(step))
        })
    }

    private static func step(_ payload: PlanAdjustmentProposal.CreateWorkout.Step) throws -> WorkoutRecipe.Step {
        let role: WorkoutStepRole
        switch payload.role {
        case "warm_up": role = .warmUp
        case "work": role = .work
        case "recovery": role = .recovery
        case "cool_down": role = .coolDown
        default: throw CoachTools.ValidationError("Unknown step role \(payload.role).")
        }
        guard let zone = PaceZone(rawValue: payload.paceZone) else {
            throw CoachTools.ValidationError("Unknown pace zone \(payload.paceZone).")
        }
        switch payload.targetType {
        case "distance_km": return .distance(role, payload.targetValue, zone)
        case "duration_seconds": return .duration(role, payload.targetValue, zone)
        default: throw CoachTools.ValidationError("Unknown target type \(payload.targetType).")
        }
    }

    private static func locate(
        _ date: Date,
        in spec: TrainingPlanSpec,
        calendar: Calendar
    ) -> (week: Int, workout: Int)? {
        for weekIndex in spec.weeks.indices {
            if let workoutIndex = spec.weeks[weekIndex].workouts.firstIndex(where: {
                calendar.isDate($0.date, inSameDayAs: date)
            }) {
                return (weekIndex, workoutIndex)
            }
        }
        return nil
    }

    private static func weekIndex(for date: Date, in spec: TrainingPlanSpec, calendar: Calendar) -> Int? {
        spec.weeks.firstIndex { week in
            guard let end = calendar.date(byAdding: .day, value: 7, to: week.startDate) else { return false }
            return date >= week.startDate && date < end
        }
    }

    private static func targetDay(_ value: String?, calendar: Calendar) throws -> Date {
        guard let value else { throw CoachTools.ValidationError("Target date is required.") }
        return try CoachTools.parseDay(value, calendar: calendar)
    }

    private static func spec(date: Date, built: BuiltWorkout) -> PlannedWorkoutSpec {
        PlannedWorkoutSpec(
            date: date,
            kind: built.kind,
            distanceKm: built.distanceKm,
            paceBand: built.paceBand,
            details: built.details,
            structure: built.structure
        )
    }

    private static func toSpec(_ row: PlannedWorkout) -> PlannedWorkoutSpec? {
        guard let kind = row.kind else { return nil }
        return PlannedWorkoutSpec(
            date: row.date,
            kind: kind,
            distanceKm: row.distanceKm,
            paceBand: row.paceBand,
            details: row.details,
            structure: row.structure
        )
    }

    private static func newSnapshot(
        date: Date,
        weekIndex: Int,
        phase: TrainingPhase,
        built: BuiltWorkout
    ) -> PlanWorkoutReceiptSnapshot {
        PlanWorkoutReceiptSnapshot(
            uuid: UUID(),
            date: date,
            weekIndex: weekIndex,
            phaseRaw: phase.rawValue,
            kindRaw: built.kind.rawValue,
            distanceKm: built.distanceKm,
            paceFastSecondsPerKm: built.paceBand?.fastSecondsPerKm,
            paceSlowSecondsPerKm: built.paceBand?.slowSecondsPerKm,
            details: built.details,
            structure: built.structure,
            statusRaw: WorkoutStatus.planned.rawValue,
            manuallyOverridden: true,
            matchedActivityUUID: nil,
            shoeID: nil,
            shoeAssignmentSourceRaw: ShoeAssignmentSource.none.rawValue,
            scheduleUpdatedFromRaw: nil,
            scheduleUpdatedAt: nil,
            scheduleLock: false
        )
    }

    private static func applyBuilt(
        _ built: BuiltWorkout,
        to snapshot: inout PlanWorkoutReceiptSnapshot,
        resetCompletion: Bool
    ) {
        snapshot.kindRaw = built.kind.rawValue
        snapshot.distanceKm = built.distanceKm
        snapshot.paceFastSecondsPerKm = built.paceBand?.fastSecondsPerKm
        snapshot.paceSlowSecondsPerKm = built.paceBand?.slowSecondsPerKm
        snapshot.details = built.details
        snapshot.structure = built.structure
        if resetCompletion {
            snapshot.statusRaw = WorkoutStatus.planned.rawValue
            snapshot.matchedActivityUUID = nil
            snapshot.scheduleLock = false
        }
    }
}
