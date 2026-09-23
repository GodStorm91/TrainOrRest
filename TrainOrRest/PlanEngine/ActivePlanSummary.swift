import Foundation

enum ActivePlanStatus: String, Equatable {
    case active
    case onTrack
    case needsAttention
    case paused
    case completed

    var displayName: String {
        switch self {
        case .active: "Active"
        case .onTrack: "On track"
        case .needsAttention: "Needs adjustment"
        case .paused: "Paused"
        case .completed: "Completed"
        }
    }

    var eyebrowText: String {
        switch self {
        case .active: "PLAN ACTIVE"
        case .onTrack: "PLAN ON TRACK"
        case .needsAttention: "PLAN NEEDS ADJUSTMENT"
        case .paused: "PLAN PAUSED"
        case .completed: "PLAN COMPLETED"
        }
    }
}

enum PlanHealthReason: Equatable {
    case insufficientData
    case missedSessions(Int)
    case missedKeySessions(Int)
    case weeklyVolumeBehind
    case raceDatePassed
    case raceDay
}

struct PlanHealth: Equatable {
    var status: ActivePlanStatus
    var reasons: [PlanHealthReason]
    var adherenceRate: Double?
    var volumeCompliance: Double?
    var missedKeySessions: Int
    var missedWorkoutAudit: MissedWorkoutAudit
    var evaluatedAt: Date
}

enum MissedWorkoutAuditReason: String, Equatable {
    case missed
    case completed
    case futureWorkout
    case todayStillSyncing
    case skipped
    case duplicateWorkout
    case movedWorkout
    case notExpected
    case outsideCutoff
}

struct MissedWorkoutAuditEntry: Identifiable, Equatable {
    var id: UUID
    var date: Date
    var kindRaw: String
    var isKeyWorkout: Bool
    var reason: MissedWorkoutAuditReason
}

struct MissedWorkoutAudit: Equatable {
    var entries: [MissedWorkoutAuditEntry] = []

    var missed: [MissedWorkoutAuditEntry] { entries.filter { $0.reason == .missed } }
    var missedKeyWorkouts: [MissedWorkoutAuditEntry] { missed.filter(\.isKeyWorkout) }
}

struct ActivePlanSummary: Equatable {
    var title: String
    var raceDate: Date
    var targetTimeSeconds: Double
    var runningDaysPerWeek: Int
    var startDate: Date
    var endDate: Date
    var currentWeek: Int
    var totalWeeks: Int
    var timelineProgress: Double
    var daysRemaining: Int?
    var isRaceDay: Bool
    var health: PlanHealth
    var currentPhase: ActivePlanPhaseSummary?
    var thisWeek: ActivePlanWeekSummary?
    var nextWorkout: ActivePlanWorkoutSummary?
    var upcomingWorkouts: [ActivePlanWorkoutSummary]
    var weeklyProgress: [ActivePlanWeekSummary]
    var phases: [ActivePlanPhaseSummary]
}

struct ActivePlanPhaseSummary: Equatable, Identifiable {
    var id: Int { startWeekIndex }
    var phase: TrainingPhase
    var startWeekIndex: Int
    var endWeekIndex: Int
    var startDate: Date
    var endDate: Date
    var currentWeekInPhase: Int?
    var totalWeeks: Int
    var targetVolumeRangeKm: ClosedRange<Double>?

    var displayName: String { phase.displayName }
}

struct ActivePlanWeekSummary: Equatable, Identifiable {
    var id: Int { weekIndex }
    var weekIndex: Int
    var startDate: Date
    var endDate: Date
    var plannedSessions: Int
    var completedSessions: Int
    var plannedDistanceKm: Double
    var completedDistanceKm: Double
    var plannedKeySessions: Int
    var completedKeySessions: Int
    var plannedLongRunKm: Double?
    var completedLongRunKm: Double?
    var isCurrentWeek: Bool
    var isFutureWeek: Bool

    var adherenceRate: Double? {
        guard plannedSessions > 0 else { return nil }
        return Double(completedSessions) / Double(plannedSessions)
    }

    var volumeCompliance: Double? {
        guard plannedDistanceKm > 0 else { return nil }
        return completedDistanceKm / plannedDistanceKm
    }
}

struct ActivePlanWorkoutSummary: Equatable, Identifiable {
    var id: UUID
    var date: Date
    var weekIndex: Int
    var kind: WorkoutKind?
    var kindRaw: String
    var distanceKm: Double
    var paceBand: PaceBand?
    var details: String

    var displayName: String { kind?.displayName ?? kindRaw.capitalized }
}

enum ActivePlanSummaryBuilder {
    /// Conservative first-pass thresholds:
    /// - Needs adjustment: <60% due sessions, <65% due volume, or 2+ missed key workouts.
    /// - On track: 75%+ due sessions, 75%+ due volume, and no missed key workouts.
    /// - Otherwise the plan is simply Active, so existence alone never earns "On track".
    enum Tuning {
        static let needsAttentionSessionRate = 0.60
        static let needsAttentionVolumeRate = 0.65
        static let onTrackSessionRate = 0.75
        static let onTrackVolumeRate = 0.75
        static let missedKeySessionLimit = 2
        static let minimumDueSessionsForAdherence = 2
    }

    static func build(
        goal: Goal?,
        plan: TrainingPlan?,
        activities: [CompletedActivity],
        today: Date = .now,
        calendar inputCalendar: Calendar = .current
    ) -> ActivePlanSummary? {
        guard let goalSpec = goal?.spec, let plan else { return nil }

        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone

        let workouts = plan.workouts.sorted { ($0.date, $0.uuid.uuidString) < ($1.date, $1.uuid.uuidString) }
        let totalWeeks = max(plan.weekTargetVolumesKm.count, (workouts.map(\.weekIndex).max() ?? -1) + 1)
        guard totalWeeks > 0 else { return nil }

        let todayStart = calendar.startOfDay(for: today)
        let planEvaluationDay = plan.pausedAt.map { calendar.startOfDay(for: $0) } ?? todayStart
        let raceDay = calendar.startOfDay(for: goalSpec.raceDate)
        let startDate = planStartDate(plan: plan, workouts: workouts, calendar: calendar)
        let endDate = planEndDate(plan: plan, goal: goalSpec, workouts: workouts, calendar: calendar)
        let currentWeekIndex = currentWeekIndex(
            plan: plan,
            workouts: workouts,
            today: planEvaluationDay,
            totalWeeks: totalWeeks,
            calendar: calendar
        )
        let phases = phaseSummaries(
            plan: plan,
            startDate: startDate,
            currentWeekIndex: currentWeekIndex,
            calendar: calendar
        )
        let completionIndex = completionIndex(workouts: workouts, activities: activities, calendar: calendar)
        let weeks = weekSummaries(
            plan: plan,
            workouts: workouts,
            activities: activities,
            completionIndex: completionIndex,
            totalWeeks: totalWeeks,
            startDate: startDate,
            today: planEvaluationDay,
            currentWeekIndex: currentWeekIndex,
            calendar: calendar
        )
        let health = evaluateHealth(
            plan: plan,
            goal: goalSpec,
            workouts: workouts,
            activities: activities,
            completionIndex: completionIndex,
            today: planEvaluationDay,
            calendar: calendar
        )
        let next = workouts
            .filter { calendar.startOfDay(for: $0.date) >= todayStart && $0.status == .planned }
            .sorted { ($0.date, $0.uuid.uuidString) < ($1.date, $1.uuid.uuidString) }
            .first

        let remaining = calendar.dateComponents([.day], from: todayStart, to: raceDay).day

        return ActivePlanSummary(
            title: title(for: goalSpec),
            raceDate: raceDay,
            targetTimeSeconds: goalSpec.targetTimeSeconds,
            runningDaysPerWeek: goalSpec.availableDays.count,
            startDate: startDate,
            endDate: endDate,
            currentWeek: min(max(currentWeekIndex + 1, 1), totalWeeks),
            totalWeeks: totalWeeks,
            timelineProgress: Double(min(max(currentWeekIndex + 1, 1), totalWeeks)) / Double(totalWeeks),
            daysRemaining: remaining.map { max($0, 0) },
            isRaceDay: remaining == 0,
            health: health,
            currentPhase: phases.first { $0.startWeekIndex...$0.endWeekIndex ~= currentWeekIndex },
            thisWeek: weeks.first { $0.weekIndex == currentWeekIndex },
            nextWorkout: next.map(workoutSummary),
            upcomingWorkouts: workouts
                .filter { calendar.startOfDay(for: $0.date) >= todayStart && $0.status == .planned }
                .sorted { ($0.date, $0.uuid.uuidString) < ($1.date, $1.uuid.uuidString) }
                .prefix(3)
                .map(workoutSummary),
            weeklyProgress: weeks,
            phases: phases
        )
    }

    private static func title(for goal: GoalSpec) -> String {
        if goal.distance == .marathon, goal.targetTimeSeconds <= 4 * 3600 {
            return "Sub-4:00 Marathon"
        }
        return "\(goal.distance.displayName) in \(Formatters.duration(goal.targetTimeSeconds))"
    }

    private static func planStartDate(plan: TrainingPlan, workouts: [PlannedWorkout], calendar: Calendar) -> Date {
        if let first = workouts.map(\.date).min() {
            return PlanGenerator.mondayOfWeek(containing: first, calendar: calendar)
        }
        return PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar)
    }

    private static func planEndDate(
        plan: TrainingPlan,
        goal: GoalSpec,
        workouts: [PlannedWorkout],
        calendar: Calendar
    ) -> Date {
        if let last = workouts.map(\.date).max() {
            return calendar.startOfDay(for: last)
        }
        return calendar.startOfDay(for: goal.raceDate)
    }

    private static func currentWeekIndex(
        plan: TrainingPlan,
        workouts: [PlannedWorkout],
        today: Date,
        totalWeeks: Int,
        calendar: Calendar
    ) -> Int {
        if let upcoming = workouts.first(where: { calendar.startOfDay(for: $0.date) >= today }) {
            return min(max(upcoming.weekIndex, 0), totalWeeks - 1)
        }
        let planStart = planStartDate(plan: plan, workouts: workouts, calendar: calendar)
        let days = calendar.dateComponents([.day], from: planStart, to: today).day ?? 0
        return min(max(days / 7, 0), totalWeeks - 1)
    }

    private static func phaseSummaries(
        plan: TrainingPlan,
        startDate: Date,
        currentWeekIndex: Int,
        calendar: Calendar
    ) -> [ActivePlanPhaseSummary] {
        guard !plan.weekPhasesRaw.isEmpty else { return [] }
        var ranges: [(phase: TrainingPhase, start: Int, end: Int)] = []
        var rangeStart = 0
        var current = TrainingPhase(rawValue: plan.weekPhasesRaw[0]) ?? .base
        for index in plan.weekPhasesRaw.indices.dropFirst() {
            let phase = TrainingPhase(rawValue: plan.weekPhasesRaw[index]) ?? current
            if phase != current {
                ranges.append((current, rangeStart, index - 1))
                rangeStart = index
                current = phase
            }
        }
        ranges.append((current, rangeStart, plan.weekPhasesRaw.count - 1))

        return ranges.map { item in
            let phaseStart = calendar.date(byAdding: .day, value: item.start * 7, to: startDate) ?? startDate
            let phaseEndStart = calendar.date(byAdding: .day, value: item.end * 7, to: startDate) ?? phaseStart
            let phaseEnd = calendar.date(byAdding: .day, value: 6, to: phaseEndStart) ?? phaseEndStart
            let volumes = plan.weekTargetVolumesKm.enumerated()
                .filter { item.start...item.end ~= $0.offset }
                .map(\.element)
                .filter { $0 > 0 }
            let targetRange: ClosedRange<Double>? = {
                guard let min = volumes.min(), let max = volumes.max() else { return nil }
                return min...max
            }()
            return ActivePlanPhaseSummary(
                phase: item.phase,
                startWeekIndex: item.start,
                endWeekIndex: item.end,
                startDate: phaseStart,
                endDate: phaseEnd,
                currentWeekInPhase: item.start...item.end ~= currentWeekIndex ? currentWeekIndex - item.start + 1 : nil,
                totalWeeks: item.end - item.start + 1,
                targetVolumeRangeKm: targetRange
            )
        }
    }

    private static func completionIndex(
        workouts: [PlannedWorkout],
        activities: [CompletedActivity],
        calendar: Calendar
    ) -> [UUID: CompletedActivity?] {
        let activityByID = Dictionary(uniqueKeysWithValues: activities.map { ($0.hkUUID, $0) })
        let alreadyMatched = Set(workouts.compactMap(\.matchedActivityUUID))
        let plannedRefs = workouts
            .filter { $0.status == .planned && $0.matchedActivityUUID == nil }
            .map(\.matcherRef)
        let activityRefs = activities
            .filter { !alreadyMatched.contains($0.hkUUID) }
            .map { WorkoutMatcher.ActivityRef(id: $0.hkUUID, date: $0.date, durationSeconds: $0.durationSeconds) }
        let autoMatches = WorkoutMatcher.matches(planned: plannedRefs, activities: activityRefs, calendar: calendar)

        var index: [UUID: CompletedActivity?] = [:]
        for workout in workouts {
            if workout.status == .done {
                index[workout.uuid] = workout.matchedActivityUUID.flatMap { activityByID[$0] }
            } else if let activityID = workout.matchedActivityUUID {
                index[workout.uuid] = activityByID[activityID]
            } else if let activityID = autoMatches[workout.uuid] {
                index[workout.uuid] = activityByID[activityID]
            }
        }
        return index
    }

    private static func weekSummaries(
        plan: TrainingPlan,
        workouts: [PlannedWorkout],
        activities: [CompletedActivity],
        completionIndex: [UUID: CompletedActivity?],
        totalWeeks: Int,
        startDate: Date,
        today: Date,
        currentWeekIndex: Int,
        calendar: Calendar
    ) -> [ActivePlanWeekSummary] {
        (0..<totalWeeks).map { index in
            let weekStart = calendar.date(byAdding: .day, value: index * 7, to: startDate) ?? startDate
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let weekWorkouts = workouts.filter { $0.weekIndex == index }
            let completed = weekWorkouts.filter { completionIndex.keys.contains($0.uuid) }
            let keyWorkouts = weekWorkouts.filter { $0.kind?.isQuality == true && $0.kind != .race }
            let completedKeys = keyWorkouts.filter { completionIndex.keys.contains($0.uuid) }
            let plannedLongRun = weekWorkouts
                .filter { $0.kind == .long }
                .map(\.distanceKm)
                .max()
            let completedLongRun = completed
                .filter { $0.kind == .long }
                .map { completionDistanceKm(for: $0, completion: completionIndex[$0.uuid] ?? nil) }
                .max()
            let plannedDistance = plan.weekTargetVolumesKm.indices.contains(index)
                ? plan.weekTargetVolumesKm[index]
                : weekWorkouts.reduce(0) { $0 + $1.distanceKm }
            let completedDistance = completed.reduce(0) { partial, workout in
                partial + completionDistanceKm(for: workout, completion: completionIndex[workout.uuid] ?? nil)
            }
            return ActivePlanWeekSummary(
                weekIndex: index,
                startDate: weekStart,
                endDate: weekEnd,
                plannedSessions: weekWorkouts.count,
                completedSessions: completed.count,
                plannedDistanceKm: plannedDistance,
                completedDistanceKm: completedDistance,
                plannedKeySessions: keyWorkouts.count,
                completedKeySessions: completedKeys.count,
                plannedLongRunKm: plannedLongRun,
                completedLongRunKm: completedLongRun,
                isCurrentWeek: index == currentWeekIndex,
                isFutureWeek: weekStart > calendar.startOfDay(for: today)
            )
        }
    }

    private static func evaluateHealth(
        plan: TrainingPlan,
        goal: GoalSpec,
        workouts: [PlannedWorkout],
        activities: [CompletedActivity],
        completionIndex: [UUID: CompletedActivity?],
        today: Date,
        calendar: Calendar
    ) -> PlanHealth {
        if plan.pausedAt != nil {
            return PlanHealth(status: .paused, reasons: [.insufficientData], adherenceRate: nil, volumeCompliance: nil, missedKeySessions: 0, missedWorkoutAudit: MissedWorkoutAudit(), evaluatedAt: today)
        }

        let raceDay = calendar.startOfDay(for: goal.raceDate)
        if raceDay < today {
            return PlanHealth(status: .completed, reasons: [.raceDatePassed], adherenceRate: nil, volumeCompliance: nil, missedKeySessions: 0, missedWorkoutAudit: MissedWorkoutAudit(), evaluatedAt: today)
        }
        if raceDay == today {
            return PlanHealth(status: .active, reasons: [.raceDay], adherenceRate: nil, volumeCompliance: nil, missedKeySessions: 0, missedWorkoutAudit: MissedWorkoutAudit(), evaluatedAt: today)
        }

        let audit = dueWorkoutAudit(
            workouts: workouts,
            completionIndex: completionIndex,
            today: today,
            calendar: calendar
        )
        let due = workouts.filter { workout in
            audit.entries.contains { $0.id == workout.uuid && ($0.reason == .missed || $0.reason == .completed) }
        }
        guard due.count >= Tuning.minimumDueSessionsForAdherence else {
            return PlanHealth(status: .active, reasons: [.insufficientData], adherenceRate: nil, volumeCompliance: nil, missedKeySessions: 0, missedWorkoutAudit: audit, evaluatedAt: today)
        }

        let completed = due.filter { completionIndex.keys.contains($0.uuid) }
        let plannedDistance = due.reduce(0) { $0 + $1.distanceKm }
        let completedDistance = completed.reduce(0) { partial, workout in
            partial + completionDistanceKm(for: workout, completion: completionIndex[workout.uuid] ?? nil)
        }
        let missed = audit.missed.count
        let missedKeys = audit.missedKeyWorkouts.count
        let adherence = Double(completed.count) / Double(due.count)
        let volume = plannedDistance > 0 ? completedDistance / plannedDistance : nil

        var reasons: [PlanHealthReason] = []
        if missed > 0 { reasons.append(.missedSessions(missed)) }
        if missedKeys > 0 { reasons.append(.missedKeySessions(missedKeys)) }
        if let volume, volume < Tuning.needsAttentionVolumeRate { reasons.append(.weeklyVolumeBehind) }

        let needsAttention = adherence < Tuning.needsAttentionSessionRate
            || (volume ?? 1) < Tuning.needsAttentionVolumeRate
            || missedKeys >= Tuning.missedKeySessionLimit
        let onTrack = adherence >= Tuning.onTrackSessionRate
            && (volume ?? 1) >= Tuning.onTrackVolumeRate
            && missedKeys == 0

        let status: ActivePlanStatus
        if needsAttention {
            status = .needsAttention
        } else if onTrack {
            status = .onTrack
        } else {
            status = .active
        }

        return PlanHealth(
            status: status,
            reasons: reasons.isEmpty ? [.insufficientData] : reasons,
            adherenceRate: adherence,
            volumeCompliance: volume,
            missedKeySessions: missedKeys,
            missedWorkoutAudit: audit,
            evaluatedAt: today
        )
    }

    static func dueWorkoutAudit(
        workouts: [PlannedWorkout],
        completionIndex: [UUID: CompletedActivity?],
        today: Date,
        calendar: Calendar
    ) -> MissedWorkoutAudit {
        let cutoff = calendar.startOfDay(for: today)
        var seenExpectedKeys: Set<String> = []
        let entries = workouts.sorted { ($0.date, $0.uuid.uuidString) < ($1.date, $1.uuid.uuidString) }.map { workout -> MissedWorkoutAuditEntry in
            let day = calendar.startOfDay(for: workout.date)
            let key = "\(Int(day.timeIntervalSince1970))-\(workout.kindRaw)-\(String(format: "%.2f", workout.distanceKm))"
            let reason: MissedWorkoutAuditReason
            if workout.status == .skipped {
                reason = .skipped
            } else if day > cutoff {
                reason = .futureWorkout
            } else if day == cutoff && !completionIndex.keys.contains(workout.uuid) {
                reason = .todayStillSyncing
            } else if workout.scheduleUpdatedFrom != nil && day < cutoff && !completionIndex.keys.contains(workout.uuid) {
                reason = .movedWorkout
            } else if !seenExpectedKeys.insert(key).inserted {
                reason = .duplicateWorkout
            } else if completionIndex.keys.contains(workout.uuid) || workout.status == .done {
                reason = .completed
            } else if day < cutoff {
                reason = .missed
            } else {
                reason = .outsideCutoff
            }
            return MissedWorkoutAuditEntry(
                id: workout.uuid,
                date: workout.date,
                kindRaw: workout.kindRaw,
                isKeyWorkout: workout.kind?.isQuality == true,
                reason: reason
            )
        }
        return MissedWorkoutAudit(entries: entries)
    }

    private static func completionDistanceKm(for workout: PlannedWorkout, completion: CompletedActivity?) -> Double {
        if let meters = completion?.distanceMeters, meters > 0 {
            return meters / 1000
        }
        return workout.distanceKm
    }

    private static func workoutSummary(_ workout: PlannedWorkout) -> ActivePlanWorkoutSummary {
        ActivePlanWorkoutSummary(
            id: workout.uuid,
            date: workout.date,
            weekIndex: workout.weekIndex,
            kind: workout.kind,
            kindRaw: workout.kindRaw,
            distanceKm: workout.distanceKm,
            paceBand: workout.paceBand,
            details: workout.details
        )
    }
}

extension TrainingPhase {
    var summaryPurpose: String {
        switch self {
        case .base:
            return "Build durable aerobic volume before the harder race-specific work arrives."
        case .build:
            return "Add controlled quality while weekly volume keeps moving toward race demand."
        case .peak:
            return "Sharpen the key race-specific sessions while protecting recovery between hard days."
        case .taper:
            return "Reduce fatigue while keeping enough rhythm to arrive fresh on race day."
        }
    }
}
