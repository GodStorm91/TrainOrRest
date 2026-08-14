import Foundation
import SwiftData

/// Orchestrates the daily readiness → regeneration pipeline between SwiftData
/// and the pure engines. Logic lives in `Readiness/` and `PlanEngine/`; this
/// file fetches, maps, and persists.
@MainActor
enum ReadinessStore {
    /// Computes today's readiness, rotates the diff snapshot once per day,
    /// and regenerates the future schedule. Returns the persisted verdict
    /// row (nil when there is nothing to compute yet).
    @discardableResult
    static func runDailyPipeline(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> DailyReadiness? {
        try backfillMissingScores(in: context)
        let readiness = try computeAndPersistReadiness(in: context, today: today, calendar: calendar)
        try regenerateIfNeeded(in: context, verdict: readiness?.verdict ?? .insufficientData, today: today, calendar: calendar)
        try context.save()
        return readiness
    }

    /// One-time upgrade path: readiness rows recorded before the score feature
    /// have `score == nil`. Recompute it from each row's stored snapshot so the
    /// Trends history isn't blank after updating. Idempotent.
    private static func backfillMissingScores(in context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<DailyReadiness>(
            predicate: #Predicate { $0.score == nil && $0.verdictRaw != "insufficientData" }
        ))
        for row in rows {
            let snapshot = ReadinessAssessment.Snapshot(
                hrvMean7: row.hrvMean7, hrvMean28: row.hrvMean28,
                rhrMean7: row.rhrMean7, rhrMean28: row.rhrMean28,
                sleepLastNight: row.sleepLastNight, sleepMean14: row.sleepMean14,
                acuteChronicRatio: row.acuteChronicRatio
            )
            row.score = ReadinessScore.score(snapshot: snapshot, verdict: row.verdict)
        }
    }

    // MARK: - Readiness

    private static func computeAndPersistReadiness(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> DailyReadiness? {
        let wellnessRows = try context.fetch(FetchDescriptor<DailyWellness>())
        let samples = wellnessRows.map {
            WellnessSample(
                date: $0.date,
                hrvSDNN: $0.hrvSDNN,
                restingHeartRate: $0.restingHeartRate,
                sleepHours: $0.sleepHours
            )
        }

        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }
        let loads = try context.fetch(FetchDescriptor<CompletedActivity>()).map { activity in
            (
                date: activity.date,
                load: TrainingLoad.sessionLoad(
                    durationSeconds: activity.durationSeconds,
                    avgPaceSecondsPerKm: activity.avgPaceSecondsPerKm,
                    paces: paces
                )
            )
        }

        let checkIns = try todayCheckInSignals(in: context, today: today, calendar: calendar)
        let hasStandaloneCheckIn = checkIns.contains { $0.role == .standalone }
        guard !samples.isEmpty || !loads.isEmpty || hasStandaloneCheckIn else { return nil }

        let assessment = ReadinessEngine.assess(
            wellness: samples, loads: loads, today: today, calendar: calendar, checkIns: checkIns
        )

        let day = calendar.startOfDay(for: today)
        var descriptor = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.date == day })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.update(from: assessment, computedAt: today)
            return existing
        }
        let row = DailyReadiness(date: day, assessment: assessment, computedAt: today)
        context.insert(row)
        return row
    }

    private static func todayCheckInSignals(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> [CheckInSignal] {
        let day = calendar.startOfDay(for: today)
        var descriptor = FetchDescriptor<DailyCheckIn>(predicate: #Predicate { $0.date == day })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.signals ?? []
    }

    // MARK: - Regeneration

    private static func regenerateIfNeeded(
        in context: ModelContext,
        verdict: ReadinessVerdict,
        today: Date,
        calendar: Calendar
    ) throws {
        guard let goalSpec = try PlanStore.activeGoal(in: context)?.spec,
              let plan = try PlanStore.activePlan(in: context),
              let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        else { return }

        try rotateSnapshotIfNewDay(in: context, today: today, calendar: calendar)

        let spec = PlanRegenerator.regenerate(
            goal: goalSpec, fitness: fitness, verdict: verdict, today: today, calendar: calendar
        )
        try applyFutureSchedule(spec, to: plan, in: context, today: today, calendar: calendar)
    }

    /// Replaces future auto-managed rows with the regenerated schedule.
    /// Rows the user decided on (done/skipped/manual) and past rows are
    /// history — never touched. No-op when nothing would change.
    private static func applyFutureSchedule(
        _ spec: TrainingPlanSpec,
        to plan: TrainingPlan,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws {
        let dayStart = calendar.startOfDay(for: today)
        let future = try context.fetch(FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate { $0.date >= dayStart },
            sortBy: [SortDescriptor(\.date)]
        ))
        let kept = future.filter { $0.status != .planned || $0.manuallyOverridden }
        let keptDays = Set(kept.map { calendar.startOfDay(for: $0.date) })
        let replaceable = future.filter { $0.status == .planned && !$0.manuallyOverridden }

        let incoming = spec.weeks.flatMap { week in
            week.workouts
                .filter { !keptDays.contains(calendar.startOfDay(for: $0.date)) }
                .map { (week: week, workout: $0) }
        }

        // Skip the churn when the regenerated schedule matches what's stored.
        let unchanged = replaceable.count == incoming.count && zip(replaceable, incoming).allSatisfy { row, new in
            row.date == new.workout.date
                && row.kindRaw == new.workout.kind.rawValue
                && abs(row.distanceKm - new.workout.distanceKm) < 0.05
                && row.paceFastSecondsPerKm == new.workout.paceBand?.fastSecondsPerKm
                && row.structure == new.workout.structure
        }
        guard !unchanged else { return }

        for row in replaceable {
            context.delete(row)
        }
        for (week, workoutSpec) in incoming {
            let workout = PlannedWorkout(spec: workoutSpec, weekIndex: week.index, phase: week.phase)
            workout.plan = plan
            context.insert(workout)
        }
        plan.generatedAt = today
        plan.anchorDate = spec.anchorDate
        plan.weekPhasesRaw = spec.weeks.map(\.phase.rawValue)
        plan.weekTargetVolumesKm = spec.weeks.map(\.targetVolumeKm)
        plan.weekIsDown = spec.weeks.map(\.isDownWeek)
    }

    // MARK: - Snapshot / diff

    private static func rotateSnapshotIfNewDay(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws {
        let dayStart = calendar.startOfDay(for: today)
        let existing = try context.fetch(FetchDescriptor<PlanSnapshot>()).first
        if let existing, existing.capturedOn >= dayStart { return }

        let days = try currentScheduleEntries(in: context, from: dayStart)
            .map { entry in
                SnapshotDay(
                    date: entry.date,
                    kindRaw: entry.kind.rawValue,
                    distanceKm: entry.distanceKm,
                    paceFastSecondsPerKm: entry.paceBand?.fastSecondsPerKm,
                    paceSlowSecondsPerKm: entry.paceBand?.slowSecondsPerKm
                )
            }
        if let existing {
            existing.capturedOn = dayStart
            existing.days = days
        } else {
            context.insert(PlanSnapshot(capturedOn: dayStart, days: days))
        }
    }

    /// Diff between this morning's snapshot and the current schedule.
    static func todaysChanges(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> [PlanDiff.DayChange] {
        guard let snapshot = try context.fetch(FetchDescriptor<PlanSnapshot>()).first else { return [] }
        let previous = snapshot.days.compactMap { day -> PlanDiff.Entry? in
            guard let kind = WorkoutKind(rawValue: day.kindRaw) else { return nil }
            let band: PaceBand? = day.paceFastSecondsPerKm.flatMap { fast in
                day.paceSlowSecondsPerKm.map { PaceBand(fastSecondsPerKm: fast, slowSecondsPerKm: $0) }
            }
            return PlanDiff.Entry(date: day.date, kind: kind, distanceKm: day.distanceKm, paceBand: band)
        }
        let current = try currentScheduleEntries(in: context, from: calendar.startOfDay(for: today))

        let day = calendar.startOfDay(for: today)
        var descriptor = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.date == day })
        descriptor.fetchLimit = 1
        let verdict = try context.fetch(descriptor).first?.verdict ?? .insufficientData

        return PlanDiff.changes(
            previous: previous, current: current, today: today, todayVerdict: verdict, calendar: calendar
        )
    }

    private static func currentScheduleEntries(
        in context: ModelContext,
        from dayStart: Date
    ) throws -> [PlanDiff.Entry] {
        try context.fetch(FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate { $0.date >= dayStart },
            sortBy: [SortDescriptor(\.date)]
        )).compactMap { row in
            guard let kind = row.kind else { return nil }
            return PlanDiff.Entry(
                date: row.date, kind: kind, distanceKm: row.distanceKm, paceBand: row.paceBand
            )
        }
    }
}
