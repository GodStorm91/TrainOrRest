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
        return issues
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
