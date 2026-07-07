import Foundation

/// Deterministic race-backward plan generator. Pure function of
/// (goal, fitness, today, calendar): same inputs → identical plan.
///
/// Methodology parameters live in `Tuning` so they can be adjusted in one
/// place without touching placement logic.
enum PlanGenerator {
    enum Tuning {
        /// Max week-over-week volume increase.
        static let rampFactor = 1.10
        /// Every 4th building week is a recovery (down) week at this factor.
        static let downWeekFactor = 0.8
        static let downWeekInterval = 4
        /// Long run as a fraction of weekly volume.
        static let longRunFraction = 0.30
        /// Hard cap on any long run, km (marathon-plan ceiling).
        static let longRunCapKm = 32.0
        /// Weekly volume never planned below this, km.
        static let volumeFloorKm = 15.0
        /// A second weekly quality session needs at least this much volume.
        static let secondQualityMinVolumeKm = 30.0
        /// Minimum distance for a planned easy run; shorter days become rest.
        static let minEasyRunKm = 4.0
        static let warmupCooldownKm = 4.0 // 2 km each side on quality days
        /// Race-week shakeout runs stay within this range, km.
        static let shakeoutRangeKm = 4.0...8.0
        /// Hard sessions (long/quality/race) need this many days between them.
        static let hardDayGapDays = 2
        /// Peak weekly volume caps by race distance, km.
        static func peakCapKm(for distance: RaceDistance) -> Double {
            switch distance {
            case .fiveK: 55
            case .tenK: 65
            case .halfMarathon: 80
            case .marathon: 95
            }
        }
        /// Taper length in weeks (including race week) by distance.
        static func taperWeeks(for distance: RaceDistance) -> Int {
            switch distance {
            case .fiveK, .tenK: 1
            case .halfMarathon: 2
            case .marathon: 3
            }
        }
        /// Taper volume as fraction of peak, indexed from race week backward.
        static let taperFactors = [0.35, 0.6, 0.75]
    }

    static func generate(
        goal: GoalSpec,
        fitness: FitnessProfile,
        today: Date,
        calendar: Calendar
    ) -> TrainingPlanSpec {
        let anchor = calendar.startOfDay(for: today)
        let raceDay = calendar.startOfDay(for: goal.raceDate)
        guard raceDay >= anchor else {
            return TrainingPlanSpec(goal: goal, anchorDate: anchor, weeks: [])
        }

        let firstWeekStart = mondayOfWeek(containing: anchor, calendar: calendar)
        let raceWeekStart = mondayOfWeek(containing: raceDay, calendar: calendar)
        let weekCount = (calendar.dateComponents([.day], from: firstWeekStart, to: raceWeekStart).day ?? 0) / 7 + 1

        let phases = phaseByWeek(weekCount: weekCount, distance: goal.distance)
        let volumes = volumeByWeek(weekCount: weekCount, phases: phases, goal: goal, fitness: fitness)
        let paces = VDOTTable.trainingPaces(vdot: fitness.vdot)

        var weeks: [WeekPlan] = []
        for index in 0..<weekCount {
            let weekStart = calendar.date(byAdding: .day, value: index * 7, to: firstWeekStart)!
            let isPartial = index == 0 && anchor > weekStart
            let isRaceWeek = index == weekCount - 1
            var volume = volumes[index]

            // Prorate a partial first week by the share of run days remaining.
            let allRunDates = dates(for: goal.availableDays, weekStart: weekStart, calendar: calendar)
            let runDates = allRunDates.filter { $0 >= anchor && $0 < raceDay }
            if isPartial && !allRunDates.isEmpty {
                volume = rounded(volume * Double(runDates.count) / Double(allRunDates.count))
            }

            let workouts = composeWeek(
                runDates: runDates,
                volume: volume,
                phase: phases[index],
                isRaceWeek: isRaceWeek,
                raceDay: raceDay,
                goal: goal,
                paces: paces,
                calendar: calendar
            )

            weeks.append(WeekPlan(
                startDate: weekStart,
                index: index,
                phase: phases[index],
                isDownWeek: isDownWeek(index: index, phases: phases),
                isPartial: isPartial,
                targetVolumeKm: volume,
                workouts: workouts
            ))
        }

        let plan = TrainingPlanSpec(goal: goal, anchorDate: anchor, weeks: weeks)
        assert(
            PlanValidator.validate(plan, calendar: calendar).isEmpty,
            "Generated plan violates validator invariants"
        )
        return plan
    }

    // MARK: - Phases

    /// Race-backward phase split: taper by distance, then peak/build/base.
    static func phaseByWeek(weekCount: Int, distance: RaceDistance) -> [TrainingPhase] {
        let taper = min(Tuning.taperWeeks(for: distance), weekCount)
        let remaining = weekCount - taper
        let peak = min(3, remaining / 4)
        let build = min(6, (remaining - peak) * 2 / 3)
        let base = remaining - peak - build
        return Array(repeating: TrainingPhase.base, count: base)
            + Array(repeating: .build, count: build)
            + Array(repeating: .peak, count: peak)
            + Array(repeating: .taper, count: taper)
    }

    static func isDownWeek(index: Int, phases: [TrainingPhase]) -> Bool {
        phases[index] != .taper && index % Tuning.downWeekInterval == Tuning.downWeekInterval - 1
    }

    /// Weekly training volumes: ramp ≤10% from current volume toward the
    /// distance cap, down-week every 4th, taper fractions of peak at the end.
    static func volumeByWeek(
        weekCount: Int,
        phases: [TrainingPhase],
        goal: GoalSpec,
        fitness: FitnessProfile
    ) -> [Double] {
        let cap = Tuning.peakCapKm(for: goal.distance)
        var trajectory = min(max(fitness.weeklyVolumeKm, Tuning.volumeFloorKm), cap)
        var peakVolume = trajectory
        var volumes: [Double] = []

        for index in 0..<weekCount {
            if phases[index] == .taper {
                let weeksFromRace = weekCount - 1 - index
                let factor = Tuning.taperFactors[min(weeksFromRace, Tuning.taperFactors.count - 1)]
                volumes.append(rounded(peakVolume * factor))
            } else if isDownWeek(index: index, phases: phases) {
                volumes.append(rounded(trajectory * Tuning.downWeekFactor))
            } else {
                if index > 0 {
                    trajectory = min(trajectory * Tuning.rampFactor, cap)
                }
                volumes.append(rounded(trajectory))
                peakVolume = max(peakVolume, trajectory)
            }
        }
        return volumes
    }

    // MARK: - Week composition

    private static func composeWeek(
        runDates: [Date],
        volume: Double,
        phase: TrainingPhase,
        isRaceWeek: Bool,
        raceDay: Date,
        goal: GoalSpec,
        paces: TrainingPaces,
        calendar: Calendar
    ) -> [PlannedWorkoutSpec] {
        if isRaceWeek {
            return raceWeek(runDates: runDates, volume: volume, raceDay: raceDay, goal: goal, paces: paces)
        }
        guard !runDates.isEmpty else { return [] }

        var workouts: [PlannedWorkoutSpec] = []
        var remainingVolume = volume

        // Long run on the preferred day — unless it lands too close to the
        // race or was cut from a partial first week.
        let longDate = runDates.first {
            weekday(of: $0, calendar: calendar) == goal.longRunDay
                && daysBetween($0, raceDay, calendar: calendar) >= Tuning.hardDayGapDays
        }
        if let longDate {
            let longKm = min(rounded(volume * Tuning.longRunFraction), Tuning.longRunCapKm)
            workouts.append(PlannedWorkoutSpec(
                date: longDate,
                kind: .long,
                distanceKm: longKm,
                paceBand: paces.easy,
                details: "Long run at E pace"
            ))
            remainingVolume -= longKm
        }

        // Quality sessions: spacing is solved on the weekly day-circle so the
        // pattern stays safe across week boundaries (long Sun → no Mon quality).
        let kinds = qualitySessions(phase: phase, availableDayCount: goal.availableDays.count, weekVolume: volume)
        let qualityDays = qualityWeekdays(available: goal.availableDays, longRunDay: goal.longRunDay, count: kinds.count)
        var qualityDates: [Date] = []
        for (kind, day) in zip(kinds, qualityDays) {
            guard let date = runDates.first(where: {
                weekday(of: $0, calendar: calendar) == day
                    && daysBetween($0, raceDay, calendar: calendar) >= Tuning.hardDayGapDays
            }) else { continue }
            let workout = qualityWorkout(kind: kind, date: date, weekVolume: volume, paces: paces)
            workouts.append(workout)
            qualityDates.append(date)
            remainingVolume -= workout.distanceKm
        }

        // Remaining run days are easy; drop days rather than plan junk miles.
        var easyDates = runDates.filter { $0 != longDate && !qualityDates.contains($0) }
        while !easyDates.isEmpty, remainingVolume / Double(easyDates.count) < Tuning.minEasyRunKm {
            easyDates.removeLast()
        }
        if !easyDates.isEmpty {
            let perRun = rounded(remainingVolume / Double(easyDates.count))
            for date in easyDates {
                workouts.append(easyRun(date: date, distanceKm: perRun, paces: paces))
            }
        }

        return workouts.sorted { $0.date < $1.date }
    }

    private static func raceWeek(
        runDates: [Date],
        volume: Double,
        raceDay: Date,
        goal: GoalSpec,
        paces: TrainingPaces
    ) -> [PlannedWorkoutSpec] {
        var workouts: [PlannedWorkoutSpec] = []
        let shakeoutDates = runDates.suffix(2)
        if !shakeoutDates.isEmpty {
            let perRun = rounded(min(
                max(volume / Double(shakeoutDates.count), Tuning.shakeoutRangeKm.lowerBound),
                Tuning.shakeoutRangeKm.upperBound
            ))
            for date in shakeoutDates {
                workouts.append(easyRun(date: date, distanceKm: perRun, paces: paces))
            }
        }
        let goalPace = goal.goalPaceSecondsPerKm
        workouts.append(PlannedWorkoutSpec(
            date: raceDay,
            kind: .race,
            distanceKm: rounded(goal.distance.kilometers),
            paceBand: PaceBand(fastSecondsPerKm: goalPace * 0.98, slowSecondsPerKm: goalPace * 1.02),
            details: "Race day: \(goal.distance.displayName) at goal pace"
        ))
        return workouts.sorted { $0.date < $1.date }
    }

    /// Quality templates per phase; a second session needs 5+ run days and
    /// enough volume to absorb it without overshooting the weekly target.
    static func qualitySessions(phase: TrainingPhase, availableDayCount: Int, weekVolume: Double) -> [WorkoutKind] {
        let maxSessions = (availableDayCount >= 5 && weekVolume >= Tuning.secondQualityMinVolumeKm) ? 2 : 1
        switch phase {
        case .base: return [.tempo]
        case .build: return Array([WorkoutKind.tempo, .tempo].prefix(maxSessions))
        case .peak: return Array([WorkoutKind.intervals, .tempo].prefix(maxSessions))
        case .taper: return [.tempo]
        }
    }

    /// Picks quality weekdays with circular spacing ≥2 days from the long-run
    /// day and each other. Circular distance makes the weekly pattern safe
    /// across week boundaries. Deterministic: max min-gap, ties → earlier day.
    static func qualityWeekdays(available: Set<Weekday>, longRunDay: Weekday, count: Int) -> [Weekday] {
        var hardDays = [longRunDay]
        var picked: [Weekday] = []
        let candidates = available
            .filter { $0 != longRunDay }
            .sorted { $0.rawValue < $1.rawValue }

        for _ in 0..<count {
            let viable = candidates.filter { candidate in
                !picked.contains(candidate) && hardDays.allSatisfy {
                    circularDayDistance($0, candidate) >= Tuning.hardDayGapDays
                }
            }
            guard let best = viable.max(by: { lhs, rhs in
                let lhsGap = hardDays.map { circularDayDistance($0, lhs) }.min() ?? .max
                let rhsGap = hardDays.map { circularDayDistance($0, rhs) }.min() ?? .max
                return (lhsGap, rhs.rawValue) < (rhsGap, lhs.rawValue)
            }) else { break } // spacing impossible → fewer quality sessions
            picked.append(best)
            hardDays.append(best)
        }
        return picked
    }

    static func circularDayDistance(_ a: Weekday, _ b: Weekday) -> Int {
        let diff = abs(a.rawValue - b.rawValue)
        return min(diff, 7 - diff)
    }

    private static func qualityWorkout(
        kind: WorkoutKind, date: Date, weekVolume: Double, paces: TrainingPaces
    ) -> PlannedWorkoutSpec {
        switch kind {
        case .tempo:
            let tempoKm = rounded(min(max(weekVolume * 0.12, 3), 8))
            return PlannedWorkoutSpec(
                date: date,
                kind: .tempo,
                distanceKm: rounded(tempoKm + Tuning.warmupCooldownKm),
                paceBand: paces.threshold,
                details: "2 km warm-up · \(formatKm(tempoKm)) km at T pace · 2 km cool-down"
            )
        case .intervals:
            let repCount = max(3, min(6, Int(weekVolume * 0.08)))
            return PlannedWorkoutSpec(
                date: date,
                kind: .intervals,
                distanceKm: rounded(Double(repCount) + Tuning.warmupCooldownKm),
                paceBand: paces.interval,
                details: "2 km warm-up · \(repCount) × 1 km at I pace (2–3 min jog) · 2 km cool-down"
            )
        default:
            fatalError("Not a quality template: \(kind)")
        }
    }

    private static func easyRun(date: Date, distanceKm: Double, paces: TrainingPaces) -> PlannedWorkoutSpec {
        PlannedWorkoutSpec(
            date: date,
            kind: .easy,
            distanceKm: distanceKm,
            paceBand: paces.easy,
            details: "Easy run at E pace"
        )
    }

    // MARK: - Date helpers

    static func mondayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekdayNumber = calendar.component(.weekday, from: day)
        let daysFromMonday = (weekdayNumber + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: day)!
    }

    static func dates(for days: Set<Weekday>, weekStart: Date, calendar: Calendar) -> [Date] {
        (0..<7).compactMap { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            return days.contains(weekday(of: date, calendar: calendar)) ? date : nil
        }
    }

    static func weekday(of date: Date, calendar: Calendar) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date))!
    }

    static func daysBetween(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Round to 0.1 km so plans display cleanly and compare exactly.
    static func rounded(_ km: Double) -> Double {
        (km * 10).rounded() / 10
    }

    private static func formatKm(_ km: Double) -> String {
        km.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(km)) : String(format: "%.1f", km)
    }
}
