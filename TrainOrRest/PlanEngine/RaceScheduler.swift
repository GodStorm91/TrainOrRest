import Foundation

enum RaceScheduler {
    struct PlanDay: Equatable {
        var date: Date
        var kind: WorkoutKind
        var kilometers: Double
        var summary: String
    }

    private struct CandidateChange {
        var change: RaceDayChange
        var priority: RacePriority
        var raceDate: Date
    }

    private enum RecoveryMode {
        case restThenEasy, easyOnly
    }

    private static let initialRestRecoveryDays = 2

    static func suggestPriority(
        for date: Date,
        races: [RaceSpec],
        today: Date,
        calendar: Calendar
    ) -> RacePrioritySuggestion {
        let candidateDay = calendar.startOfDay(for: date)
        let upcoming = upcomingRaces(races, today: today, calendar: calendar)
        guard let aRace = upcoming.first(where: { $0.priority == .a }) else {
            return RacePrioritySuggestion(priority: .a, reason: .noARaceYet, weeksToARace: nil)
        }

        let aRaceDay = calendar.startOfDay(for: aRace.date)
        if isInsideTaper(candidateDay, for: aRace, calendar: calendar) {
            return RacePrioritySuggestion(priority: .c, reason: .insideARaceTaper, weeksToARace: nil)
        }

        if upcoming.contains(where: { race in
            let gap = dayGap(from: calendar.startOfDay(for: race.date), to: candidateDay, calendar: calendar)
            let recoveryDays = RaceTaperTable.recoveryDays(
                meters: race.distanceMeters,
                priority: race.priority
            )
            return gap > 0 && gap <= recoveryDays
        }) {
            return RacePrioritySuggestion(priority: .c, reason: .insideRecoveryWindow, weeksToARace: nil)
        }

        let weeks = abs(dayGap(from: aRaceDay, to: candidateDay, calendar: calendar)) / 7
        if weeks >= 3 {
            return RacePrioritySuggestion(priority: .b, reason: .farFromARace, weeksToARace: weeks)
        }
        return RacePrioritySuggestion(priority: .c, reason: .closeToARace, weeksToARace: weeks)
    }

    static func warnings(
        races: [RaceSpec],
        today: Date,
        calendar: Calendar
    ) -> [RaceWarning] {
        let upcoming = upcomingRaces(races, today: today, calendar: calendar)
        let aRaces = upcoming.filter { $0.priority == .a }
        var warningsByID: [String: RaceWarning] = [:]

        func add(_ warning: RaceWarning) {
            warningsByID[warning.id] = warning
        }

        for race in upcoming where race.priority != .a {
            let raceDay = calendar.startOfDay(for: race.date)
            for aRace in aRaces where race.id != aRace.id {
                guard isInsideTaper(raceDay, for: aRace, calendar: calendar) else { continue }
                add(RaceWarning(
                    code: .insideARaceTaper,
                    raceID: race.id,
                    otherRaceID: aRace.id,
                    dayGap: abs(dayGap(
                        from: raceDay,
                        to: calendar.startOfDay(for: aRace.date),
                        calendar: calendar
                    ))
                ))
            }
        }

        for earlierIndex in upcoming.indices {
            let earlier = upcoming[earlierIndex]
            let earlierDay = calendar.startOfDay(for: earlier.date)
            for later in upcoming.dropFirst(earlierIndex + 1) {
                let laterDay = calendar.startOfDay(for: later.date)
                let gap = dayGap(from: earlierDay, to: laterDay, calendar: calendar)

                if gap <= 7 {
                    add(RaceWarning(
                        code: .racesTooClose,
                        raceID: later.id,
                        otherRaceID: earlier.id,
                        dayGap: gap
                    ))
                }

                if earlier.standardDistance == .marathon,
                   later.distanceMeters >= RaceDistance.halfMarathon.meters,
                   gap > 0,
                   gap <= 28 {
                    add(RaceWarning(
                        code: .tooSoonAfterMarathon,
                        raceID: later.id,
                        otherRaceID: earlier.id,
                        dayGap: gap
                    ))
                }

                let recoveryDays = RaceTaperTable.recoveryDays(
                    meters: earlier.distanceMeters,
                    priority: earlier.priority
                )
                if gap > 0, gap <= recoveryDays {
                    add(RaceWarning(
                        code: .insideRecoveryWindow,
                        raceID: later.id,
                        otherRaceID: earlier.id,
                        dayGap: gap
                    ))
                }
            }
        }

        return warningsByID.values.sorted { lhs, rhs in
            let lhsRace = upcoming.first(where: { $0.id == lhs.raceID })
            let rhsRace = upcoming.first(where: { $0.id == rhs.raceID })
            let lhsDay = lhsRace.map { calendar.startOfDay(for: $0.date) } ?? .distantFuture
            let rhsDay = rhsRace.map { calendar.startOfDay(for: $0.date) } ?? .distantFuture
            if lhsDay != rhsDay { return lhsDay < rhsDay }
            if lhs.code.rawValue != rhs.code.rawValue { return lhs.code.rawValue < rhs.code.rawValue }
            if lhs.otherRaceID?.uuidString != rhs.otherRaceID?.uuidString {
                return (lhs.otherRaceID?.uuidString ?? "") < (rhs.otherRaceID?.uuidString ?? "")
            }
            return lhs.raceID.uuidString < rhs.raceID.uuidString
        }
    }

    static func schedule(
        races: [RaceSpec],
        planDays: [PlanDay],
        today: Date,
        calendar: Calendar
    ) -> RaceScheduleChange {
        let planByDay = planDaysByDate(planDays, calendar: calendar)
        let upcoming = upcomingRaces(races, today: today, calendar: calendar)
        var candidates: [CandidateChange] = []

        for race in upcoming {
            let raceDay = calendar.startOfDay(for: race.date)
            switch race.priority {
            case .a:
                candidates += aRaceChanges(
                    race,
                    raceDay: raceDay,
                    planByDay: planByDay,
                    calendar: calendar
                )
            case .b:
                candidates += bRaceChanges(
                    race,
                    raceDay: raceDay,
                    planByDay: planByDay,
                    calendar: calendar
                )
            case .c:
                candidates += cRaceChanges(
                    race,
                    raceDay: raceDay,
                    planByDay: planByDay,
                    calendar: calendar
                )
            }
        }

        let todayDay = calendar.startOfDay(for: today)
        var selectedByDay: [Date: CandidateChange] = [:]
        for candidate in candidates.sorted(by: candidatePrecedes) where candidate.change.date >= todayDay {
            if planByDay[candidate.change.date]?.kind == .race, intentRank(candidate.change.intent) != 0 { continue }
            selectedByDay[candidate.change.date] = selectedByDay[candidate.change.date] ?? candidate
        }
        let dayChanges = selectedByDay.values
            .map(\.change)
            .sorted { $0.date < $1.date }
        return RaceScheduleChange(
            dayChanges: dayChanges,
            warnings: warnings(races: races, today: today, calendar: calendar)
        )
    }

    private static func aRaceChanges(
        _ race: RaceSpec,
        raceDay: Date,
        planByDay: [Date: PlanDay],
        calendar: Calendar
    ) -> [CandidateChange] {
        let taperDays = daysBefore(
            raceDay,
            count: RaceTaperTable.taperDays(meters: race.distanceMeters),
            calendar: calendar
        )
        var changes = taperDays.compactMap { day -> CandidateChange? in
            guard let planDay = planByDay[day], isQualitySession(planDay.kind) else { return nil }
            let kilometers = rounded(planDay.kilometers * 0.6)
            return candidate(
                date: day,
                intent: .taper,
                race: race,
                raceDay: raceDay,
                beforeSummary: planDay.summary,
                afterSummary: workoutSummary(kind: .easy, kilometers: kilometers),
                afterKilometers: kilometers
            )
        }
        changes.append(raceDayChange(race, raceDay: raceDay, planDay: planByDay[raceDay]))
        changes += recoveryChanges(
            for: race,
            raceDay: raceDay,
            planByDay: planByDay,
            mode: .restThenEasy,
            calendar: calendar
        )
        return changes
    }

    private static func bRaceChanges(
        _ race: RaceSpec,
        raceDay: Date,
        planByDay: [Date: PlanDay],
        calendar: Calendar
    ) -> [CandidateChange] {
        let taperDays = daysBefore(
            raceDay,
            count: RaceTaperTable.miniTaperDays,
            calendar: calendar
        )
        let intensityDay = taperDays
            .compactMap { day -> (date: Date, planDay: PlanDay)? in
                guard let planDay = planByDay[day], isQualitySession(planDay.kind) else { return nil }
                return (day, planDay)
            }
            .sorted { lhs, rhs in
                if lhs.planDay.kilometers != rhs.planDay.kilometers {
                    return lhs.planDay.kilometers > rhs.planDay.kilometers
                }
                return lhs.date < rhs.date
            }
            .first?.date
        var changes = taperDays.compactMap { day -> CandidateChange? in
            guard let planDay = planByDay[day] else { return nil }
            let kilometers = rounded(planDay.kilometers * RaceTaperTable.miniTaperVolumeFactor)
            let kind: WorkoutKind
            if day == intensityDay {
                kind = planDay.kind
            } else if isQualitySession(planDay.kind) {
                kind = .easy
            } else {
                kind = planDay.kind
            }
            return candidate(
                date: day,
                intent: .miniTaper,
                race: race,
                raceDay: raceDay,
                beforeSummary: planDay.summary,
                afterSummary: workoutSummary(kind: kind, kilometers: kilometers),
                afterKilometers: kilometers
            )
        }
        changes.append(raceDayChange(race, raceDay: raceDay, planDay: planByDay[raceDay]))
        changes += recoveryChanges(
            for: race,
            raceDay: raceDay,
            planByDay: planByDay,
            mode: .restThenEasy,
            calendar: calendar
        )
        return changes
    }

    private static func cRaceChanges(
        _ race: RaceSpec,
        raceDay: Date,
        planByDay: [Date: PlanDay],
        calendar: Calendar
    ) -> [CandidateChange] {
        let planDay = planByDay[raceDay]
        let intent: RaceDayChange.Intent = planDay.map {
            $0.kind == .long || isQualitySession($0.kind)
        } == true ? .replacesQuality : .raceDay
        var changes = [raceDayChange(race, raceDay: raceDay, planDay: planDay, intent: intent)]
        changes += recoveryChanges(
            for: race,
            raceDay: raceDay,
            planByDay: planByDay,
            mode: .easyOnly,
            calendar: calendar
        )
        return changes
    }

    private static func recoveryChanges(
        for race: RaceSpec,
        raceDay: Date,
        planByDay: [Date: PlanDay],
        mode: RecoveryMode,
        calendar: Calendar
    ) -> [CandidateChange] {
        let recoveryDayCount = RaceTaperTable.recoveryDays(
            meters: race.distanceMeters,
            priority: race.priority
        )
        return daysAfter(raceDay, count: recoveryDayCount, calendar: calendar)
            .enumerated()
            .compactMap { index, day -> CandidateChange? in
                guard let planDay = planByDay[day] else { return nil }
                if case .restThenEasy = mode, index < initialRestRecoveryDays {
                    return candidate(
                        date: day,
                        intent: .recovery,
                        race: race,
                        raceDay: raceDay,
                        beforeSummary: planDay.summary,
                        afterSummary: "Rest",
                        afterKilometers: 0
                    )
                }
                let kilometers = rounded(planDay.kilometers * 0.5)
                return candidate(
                    date: day,
                    intent: .recovery,
                    race: race,
                    raceDay: raceDay,
                    beforeSummary: planDay.summary,
                    afterSummary: workoutSummary(kind: .easy, kilometers: kilometers),
                    afterKilometers: kilometers
                )
            }
    }

    private static func raceDayChange(
        _ race: RaceSpec,
        raceDay: Date,
        planDay: PlanDay?,
        intent: RaceDayChange.Intent = .raceDay
    ) -> CandidateChange {
        candidate(
            date: raceDay,
            intent: intent,
            race: race,
            raceDay: raceDay,
            beforeSummary: planDay?.summary,
            afterSummary: raceSummary(race),
            afterKilometers: rounded(race.kilometers)
        )
    }

    private static func candidate(
        date: Date,
        intent: RaceDayChange.Intent,
        race: RaceSpec,
        raceDay: Date,
        beforeSummary: String?,
        afterSummary: String,
        afterKilometers: Double
    ) -> CandidateChange {
        CandidateChange(
            change: RaceDayChange(
                date: date,
                intent: intent,
                raceID: race.id,
                beforeSummary: beforeSummary,
                afterSummary: afterSummary,
                afterKilometers: afterKilometers
            ),
            priority: race.priority,
            raceDate: raceDay
        )
    }

    private static func candidatePrecedes(_ lhs: CandidateChange, _ rhs: CandidateChange) -> Bool {
        if lhs.change.date != rhs.change.date { return lhs.change.date < rhs.change.date }
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        let lhsIntent = intentRank(lhs.change.intent)
        let rhsIntent = intentRank(rhs.change.intent)
        if lhsIntent != rhsIntent { return lhsIntent < rhsIntent }
        if lhs.raceDate != rhs.raceDate { return lhs.raceDate < rhs.raceDate }
        return lhs.change.raceID.uuidString < rhs.change.raceID.uuidString
    }

    private static func intentRank(_ intent: RaceDayChange.Intent) -> Int {
        switch intent {
        case .raceDay, .replacesQuality: 0
        case .recovery: 1
        case .taper, .miniTaper: 2
        }
    }

    private static func upcomingRaces(
        _ races: [RaceSpec],
        today: Date,
        calendar: Calendar
    ) -> [RaceSpec] {
        let todayDay = calendar.startOfDay(for: today)
        return races
            .filter {
                $0.status == .upcoming
                    && calendar.startOfDay(for: $0.date) >= todayDay
            }
            .sorted { lhs, rhs in
                let lhsDay = calendar.startOfDay(for: lhs.date)
                let rhsDay = calendar.startOfDay(for: rhs.date)
                if lhsDay != rhsDay { return lhsDay < rhsDay }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private static func planDaysByDate(_ planDays: [PlanDay], calendar: Calendar) -> [Date: PlanDay] {
        var byDay: [Date: PlanDay] = [:]
        for planDay in planDays.sorted(by: { planDayPrecedes($0, $1, calendar: calendar) }) {
            let day = calendar.startOfDay(for: planDay.date)
            guard byDay[day] == nil else { continue }
            byDay[day] = PlanDay(
                date: day,
                kind: planDay.kind,
                kilometers: planDay.kilometers,
                summary: planDay.summary
            )
        }
        return byDay
    }

    private static func planDayPrecedes(
        _ lhs: PlanDay,
        _ rhs: PlanDay,
        calendar: Calendar
    ) -> Bool {
        let lhsDay = calendar.startOfDay(for: lhs.date)
        let rhsDay = calendar.startOfDay(for: rhs.date)
        if lhsDay != rhsDay { return lhsDay < rhsDay }
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.kilometers != rhs.kilometers { return lhs.kilometers < rhs.kilometers }
        return lhs.summary < rhs.summary
    }

    private static func isInsideTaper(_ day: Date, for aRace: RaceSpec, calendar: Calendar) -> Bool {
        let candidateDay = calendar.startOfDay(for: day)
        let raceDay = calendar.startOfDay(for: aRace.date)
        guard let taperStart = calendar.date(
            byAdding: .day,
            value: -RaceTaperTable.taperDays(meters: aRace.distanceMeters),
            to: raceDay
        ) else { return false }
        return candidateDay >= taperStart && candidateDay < raceDay
    }

    private static func daysBefore(_ day: Date, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        return (1...count).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: day)
        }.sorted()
    }

    private static func daysAfter(_ day: Date, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        return (1...count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: day)
        }
    }

    private static func dayGap(from earlier: Date, to later: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: earlier),
            to: calendar.startOfDay(for: later)
        ).day ?? 0
    }

    private static func isQualitySession(_ kind: WorkoutKind) -> Bool {
        switch kind {
        case .tempo, .threshold, .intervals: true
        case .easy, .long, .race: false
        }
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
        return shortSummary("\(name) \(kilometerString(kilometers)) km")
    }

    private static func raceSummary(_ race: RaceSpec) -> String {
        let suffix = " \(kilometerString(race.kilometers)) km"
        let prefix = "Race: "
        let nameLimit = max(0, 59 - prefix.count - suffix.count)
        let name = String(race.name.prefix(nameLimit))
        let summary = name.isEmpty ? "Race:\(suffix)" : "\(prefix)\(name)\(suffix)"
        return shortSummary(summary)
    }

    private static func shortSummary(_ summary: String) -> String {
        String(summary.prefix(59))
    }

    private static func kilometerString(_ kilometers: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded(kilometers))
    }

    private static func rounded(_ kilometers: Double) -> Double {
        (kilometers * 10).rounded() / 10
    }
}
