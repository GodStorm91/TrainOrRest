import Foundation
import SwiftData

@MainActor
enum RacePlanApplier {
    static func planDays(in context: ModelContext, calendar: Calendar) throws -> [RaceScheduler.PlanDay] {
        guard let plan = try PlanStore.activePlan(in: context) else { return [] }
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))
        return workouts.compactMap { workout in
            guard workout.plan === plan, let kind = WorkoutKind(rawValue: workout.kindRaw) else { return nil }
            let kilometers = rounded(workout.distanceKm)
            return RaceScheduler.PlanDay(
                date: workout.date,
                kind: kind,
                kilometers: kilometers,
                summary: workoutSummary(kind: kind, kilometers: kilometers)
            )
        }
    }

    static func preview(
        in context: ModelContext,
        races: [RaceSpec],
        today: Date,
        calendar: Calendar
    ) throws -> RaceScheduleChange {
        RaceScheduler.schedule(
            races: races,
            planDays: try planDays(in: context, calendar: calendar),
            today: today,
            calendar: calendar
        )
    }

    @discardableResult
    static func apply(
        _ change: RaceScheduleChange,
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        summary: String
    ) throws -> UUID? {
        guard !change.dayChanges.isEmpty,
              let plan = try PlanStore.activePlan(in: context) else {
            return nil
        }

        let basePlanRevision = try CoachPlanRevision.current(in: context)
        let targetVolumesBefore = plan.weekTargetVolumesKm
        var workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
            .filter { $0.plan === plan }
        var operations: [PlanEditOperation] = []
        var touchedWeeks: Set<Int> = []

        do {
            for dayChange in change.dayChanges.sorted(by: { $0.date < $1.date }) {
                let day = calendar.startOfDay(for: dayChange.date)
                let current = PlannedWorkout.preferredAmongDuplicates(workouts.filter {
                    calendar.isDate($0.date, inSameDayAs: day)
                })
                let kind = workoutKind(for: dayChange)

                guard dayChange.afterKilometers > 0, let kind else {
                    guard let current else { continue }
                    let before = PlanWorkoutReceiptSnapshot(workout: current)
                    context.delete(current)
                    workouts.removeAll { $0 === current }
                    operations.append(PlanEditOperation(before: before, after: nil))
                    touchedWeeks.insert(before.weekIndex)
                    continue
                }

                if let current {
                    let kindChanged = current.kindRaw != kind.rawValue
                    let distanceChanged = abs(current.distanceKm - dayChange.afterKilometers) > 0.05
                    let detailsChanged = current.details != dayChange.afterSummary
                    guard kindChanged || distanceChanged || detailsChanged else { continue }
                    let before = PlanWorkoutReceiptSnapshot(workout: current)
                    current.kindRaw = kind.rawValue
                    current.distanceKm = dayChange.afterKilometers
                    current.details = dayChange.afterSummary
                    current.manuallyOverridden = true
                    if kindChanged {
                        current.structure = []
                    }
                    let after = PlanWorkoutReceiptSnapshot(workout: current)
                    operations.append(PlanEditOperation(before: before, after: after))
                    touchedWeeks.insert(before.weekIndex)
                    continue
                }

                let (weekIndex, phase) = weekAndPhase(for: day, in: plan, calendar: calendar)
                let after = PlanWorkoutReceiptSnapshot(
                    uuid: UUID(),
                    date: day,
                    weekIndex: weekIndex,
                    phaseRaw: phase.rawValue,
                    kindRaw: kind.rawValue,
                    distanceKm: dayChange.afterKilometers,
                    paceFastSecondsPerKm: nil,
                    paceSlowSecondsPerKm: nil,
                    details: dayChange.afterSummary,
                    structure: [],
                    statusRaw: WorkoutStatus.planned.rawValue,
                    manuallyOverridden: true,
                    matchedActivityUUID: nil,
                    shoeID: nil,
                    shoeAssignmentSourceRaw: ShoeAssignmentSource.none.rawValue,
                    scheduleUpdatedFromRaw: nil,
                    scheduleUpdatedAt: nil,
                    scheduleLock: false
                )
                let created = after.makeWorkout(plan: plan)
                context.insert(created)
                workouts.append(created)
                operations.append(PlanEditOperation(before: nil, after: after))
                touchedWeeks.insert(weekIndex)
            }

            guard !operations.isEmpty else { return nil }

            let weekRows = Dictionary(grouping: workouts, by: { calendar.startOfDay(for: $0.date) })
                .compactMap { PlannedWorkout.preferredAmongDuplicates($0.value) }
            let weekTargets = touchedWeeks.sorted().compactMap { weekIndex -> PlanEditWeekTarget? in
                guard targetVolumesBefore.indices.contains(weekIndex) else { return nil }
                let after = weekRows
                    .filter { $0.weekIndex == weekIndex }
                    .reduce(0) { $0 + $1.distanceKm }
                guard abs(after - targetVolumesBefore[weekIndex]) > 0.05 else { return nil }
                return PlanEditWeekTarget(
                    weekIndex: weekIndex,
                    before: targetVolumesBefore[weekIndex],
                    after: after
                )
            }
            let transaction = PlanEditTransaction(operations: operations, weekTargets: weekTargets)
            let operationData = try PlanEditReceiptCodec.encode(transaction)
            let storedTransaction = try PlanEditReceiptCodec.decode(operationData)
            let edit = PlanEdit(
                appliedAt: today,
                transaction: storedTransaction,
                operationData: operationData,
                summary: summary,
                basePlanRevision: basePlanRevision,
                source: "race"
            )

            context.insert(edit)
            var targetVolumes = plan.weekTargetVolumesKm
            for target in storedTransaction.weekTargets {
                targetVolumes[target.weekIndex] = target.after
            }
            plan.weekTargetVolumesKm = targetVolumes
            plan.generatedAt = today
            edit.appliedPlanRevision = try CoachPlanRevision.current(in: context)
            try context.save()
            NotificationCenter.default.post(name: .planDidChange, object: nil)
            return edit.id
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func workoutKind(for change: RaceDayChange) -> WorkoutKind? {
        switch change.intent {
        case .raceDay, .replacesQuality:
            return .race
        case .taper, .miniTaper, .recovery:
            let word = change.afterSummary
                .split(whereSeparator: \.isWhitespace)
                .first
            let name = word.map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            return switch name {
            case "Easy": .easy
            case "Long": .long
            case "Tempo": .tempo
            case "Threshold": .threshold
            case "Intervals": .intervals
            case "Race": .race
            case "Rest": nil
            default: nil
            }
        }
    }

    private static func weekAndPhase(
        for date: Date,
        in plan: TrainingPlan,
        calendar: Calendar
    ) -> (weekIndex: Int, phase: TrainingPhase) {
        if let weekIndex = plan.weekIndex(containing: date, calendar: calendar) {
            return (weekIndex, plan.phase(forWeek: weekIndex) ?? .base)
        }
        let planStart = PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
        let days = calendar.dateComponents([.day], from: planStart, to: date).day ?? 0
        let weekIndex = max(0, days / 7)
        let lastWeekIndex = max(plan.weekPhasesRaw.count - 1, 0)
        return (weekIndex, plan.phase(forWeek: lastWeekIndex) ?? .base)
    }

    private static func workoutSummary(kind: WorkoutKind, kilometers: Double) -> String {
        guard kilometers > 0 else { return "Rest" }
        let name: String
        switch kind {
        case .easy: name = "Easy"
        case .long: name = "Long"
        case .tempo: name = "Tempo"
        case .threshold: name = "Threshold"
        case .intervals: name = "Intervals"
        case .race: name = "Race"
        }
        let distance = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), kilometers)
        return String("\(name) \(distance) km".prefix(59))
    }

    private static func rounded(_ kilometers: Double) -> Double {
        (kilometers * 10).rounded() / 10
    }
}
