import Foundation

/// Invariant checks over a generated plan. The generator must always produce
/// a plan that validates clean; later, chat-proposed plan edits are accepted
/// only if they also validate clean (these checks are the guardrails).
enum PlanValidator {
    /// Tolerance for 0.1 km rounding in volume comparisons.
    static let volumeEpsilonKm = 0.15
    /// A long run may not exceed this share of its week's target volume.
    static let longRunMaxFraction = 0.40

    struct Issue: Equatable, CustomStringConvertible {
        enum Kind: Equatable {
            case workoutOnUnavailableDay
            case longRunTooLong
            case rampExceeded
            case taperNotMonotonic
            case qualityTooClose
            case raceMissing
            case weeklyVolumeTooHigh
            case duplicateWorkoutDay
            case workoutOutsidePlanWeek
            case invalidDistance
            case structureDistanceMismatch
        }

        var kind: Kind
        var weekIndex: Int?
        var message: String

        var description: String { message }
    }

    static func validate(
        _ plan: TrainingPlanSpec,
        calendar: Calendar,
        peakCapKm: Double? = nil
    ) -> [Issue] {
        var issues: [Issue] = []
        issues += availabilityIssues(plan, calendar: calendar)
        issues += absoluteVolumeIssues(plan, peakCapKm: peakCapKm)
        issues += longRunIssues(plan)
        issues += rampIssues(plan)
        issues += taperIssues(plan)
        issues += qualitySpacingIssues(plan, calendar: calendar)
        issues += raceIssues(plan, calendar: calendar)
        issues += duplicateDayIssues(plan, calendar: calendar)
        issues += planWeekIssues(plan, calendar: calendar)
        issues += distanceIssues(plan)
        return issues
    }

    /// A day holds at most one workout, anywhere in the plan.
    private static func duplicateDayIssues(_ plan: TrainingPlanSpec, calendar: Calendar) -> [Issue] {
        let days = plan.weeks.flatMap(\.workouts).map { calendar.startOfDay(for: $0.date) }.sorted()
        return zip(days, days.dropFirst()).compactMap { earlier, later in
            guard earlier == later else { return nil }
            return Issue(
                kind: .duplicateWorkoutDay,
                weekIndex: nil,
                message: "Two workouts scheduled on \(dayString(earlier, calendar: calendar))"
            )
        }
    }

    /// Every workout lives in the week that actually contains its date, so week
    /// metadata (phase, target volume) always describes the right seven days.
    private static func planWeekIssues(_ plan: TrainingPlanSpec, calendar: Calendar) -> [Issue] {
        plan.weeks.flatMap { week -> [Issue] in
            guard let end = calendar.date(byAdding: .day, value: 7, to: week.startDate) else { return [] }
            return week.workouts.compactMap { workout in
                guard workout.date < week.startDate || workout.date >= end else { return nil }
                return Issue(
                    kind: .workoutOutsidePlanWeek,
                    weekIndex: week.index,
                    message: "Week \(week.index): \(workout.kind.rawValue) on \(dayString(workout.date, calendar: calendar)) is outside that week"
                )
            }
        }
    }

    /// Distances must be real numbers above zero, and a stored structure must
    /// account for exactly the distance the workout claims.
    private static func distanceIssues(_ plan: TrainingPlanSpec) -> [Issue] {
        plan.weeks.flatMap { week in
            week.workouts.flatMap { workout -> [Issue] in
                guard workout.distanceKm.isFinite, workout.distanceKm > 0 else {
                    return [Issue(
                        kind: .invalidDistance,
                        weekIndex: week.index,
                        message: "Week \(week.index): \(workout.kind.rawValue) has invalid distance"
                    )]
                }
                guard !workout.structure.isEmpty else { return [] }
                let structured = WorkoutStructure.totalDistanceKm(workout.structure)
                guard abs(structured - workout.distanceKm) > volumeEpsilonKm else { return [] }
                return [Issue(
                    kind: .structureDistanceMismatch,
                    weekIndex: week.index,
                    message: "Week \(week.index): \(workout.kind.rawValue) structure covers \(structured) km but claims \(workout.distanceKm) km"
                )]
            }
        }
    }

    private static func absoluteVolumeIssues(_ plan: TrainingPlanSpec, peakCapKm: Double?) -> [Issue] {
        guard let peakCapKm else { return [] }
        return plan.weeks.compactMap { week in
            guard !week.isPartial, week.targetVolumeKm > peakCapKm + volumeEpsilonKm else { return nil }
            return Issue(
                kind: .weeklyVolumeTooHigh,
                weekIndex: week.index,
                message: "Week \(week.index): volume \(week.targetVolumeKm) km exceeds cap \(peakCapKm) km"
            )
        }
    }

    private static func availabilityIssues(_ plan: TrainingPlanSpec, calendar: Calendar) -> [Issue] {
        plan.weeks.flatMap { week in
            week.workouts.compactMap { workout in
                let day = PlanGenerator.weekday(of: workout.date, calendar: calendar)
                guard workout.kind != .race, !plan.goal.availableDays.contains(day) else { return nil }
                return Issue(
                    kind: .workoutOnUnavailableDay,
                    weekIndex: week.index,
                    message: "Week \(week.index): \(workout.kind.rawValue) on unavailable \(day.shortName)"
                )
            }
        }
    }

    private static func longRunIssues(_ plan: TrainingPlanSpec) -> [Issue] {
        plan.weeks.flatMap { week in
            week.workouts.compactMap { workout in
                guard workout.kind == .long else { return nil }
                let cap = PlanGenerator.Tuning.longRunCapKm
                let fractionCap = week.targetVolumeKm * longRunMaxFraction
                guard workout.distanceKm > cap + volumeEpsilonKm
                    || workout.distanceKm > fractionCap + volumeEpsilonKm else { return nil }
                return Issue(
                    kind: .longRunTooLong,
                    weekIndex: week.index,
                    message: "Week \(week.index): long run \(workout.distanceKm) km exceeds cap"
                )
            }
        }
    }

    /// Ramp: non-taper weeks may grow ≤10% over the last non-down week;
    /// down weeks must not exceed it. Partial first weeks are exempt
    /// (their volume is prorated, not comparable).
    private static func rampIssues(_ plan: TrainingPlanSpec) -> [Issue] {
        var issues: [Issue] = []
        var reference: Double?
        for week in plan.weeks where week.phase != .taper && !week.isPartial {
            defer { if !week.isDownWeek { reference = week.targetVolumeKm } }
            guard let reference else { continue }
            let limit = week.isDownWeek
                ? reference + volumeEpsilonKm
                : reference * PlanGenerator.Tuning.rampFactor + volumeEpsilonKm
            if week.targetVolumeKm > limit {
                issues.append(Issue(
                    kind: .rampExceeded,
                    weekIndex: week.index,
                    message: "Week \(week.index): volume \(week.targetVolumeKm) km exceeds ramp limit \(limit) km"
                ))
            }
        }
        return issues
    }

    /// Taper: volumes non-increasing toward the race and below peak volume.
    /// Partial first weeks are exempt like in the ramp check — their volume
    /// is prorated, not comparable.
    private static func taperIssues(_ plan: TrainingPlanSpec) -> [Issue] {
        var issues: [Issue] = []
        let peak = plan.weeks
            .filter { $0.phase != .taper && !$0.isPartial }
            .map(\.targetVolumeKm)
            .max() ?? .infinity
        var previous: Double?
        for week in plan.weeks where week.phase == .taper && !week.isPartial {
            let limit = min(previous ?? peak, peak) + volumeEpsilonKm
            if week.targetVolumeKm > limit {
                issues.append(Issue(
                    kind: .taperNotMonotonic,
                    weekIndex: week.index,
                    message: "Week \(week.index): taper volume \(week.targetVolumeKm) km not decreasing"
                ))
            }
            previous = week.targetVolumeKm
        }
        return issues
    }

    /// Hard sessions (long, tempo, intervals, race) need ≥1 recovery day
    /// between them, checked globally across week boundaries.
    private static func qualitySpacingIssues(_ plan: TrainingPlanSpec, calendar: Calendar) -> [Issue] {
        let hardDates = plan.weeks
            .flatMap(\.workouts)
            .filter { $0.kind.isQuality }
            .map(\.date)
            .sorted()
        return zip(hardDates, hardDates.dropFirst()).compactMap { earlier, later in
            let gap = PlanGenerator.daysBetween(earlier, later, calendar: calendar)
            guard gap < PlanGenerator.Tuning.hardDayGapDays else { return nil }
            return Issue(
                kind: .qualityTooClose,
                weekIndex: nil,
                message: "Hard sessions \(gap) day(s) apart around \(earlier)"
            )
        }
    }

    /// Local `YYYY-MM-DD` for issue messages. The engine stays free of the
    /// main-actor chat layer, so it formats dates itself.
    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func raceIssues(_ plan: TrainingPlanSpec, calendar: Calendar) -> [Issue] {
        guard !plan.weeks.isEmpty else { return [] }
        let raceDay = calendar.startOfDay(for: plan.goal.raceDate)
        let races = plan.weeks.flatMap(\.workouts).filter { $0.kind == .race }
        guard races.count != 1 || races.first?.date != raceDay else { return [] }
        return [Issue(
            kind: .raceMissing,
            weekIndex: plan.weeks.last?.index,
            message: "Plan must contain exactly one race workout on race day"
        )]
    }
}
