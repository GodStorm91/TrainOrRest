import Foundation
import SwiftData

@MainActor
enum CoachContextBuilder {
    static let maxCharacters = 8000

    static func build(in context: ModelContext, today: Date, calendar: Calendar) throws -> String {
        var lines: [String] = [
            "You are TrainOrRest, a cautious running coach. Explain decisions from the user's actual data.",
            "Use plan tools only for schedule changes. Never claim a plan edit was applied unless a tool result confirms it.",
            "When the user wants to update the training calendar, call the plan tool instead of giving CSV/import instructions. The app will ask the user to confirm before saving the proposed change.",
            "Never output ICS/iCalendar/VCALENDAR text, Google Calendar import steps, or manual calendar-import instructions for training schedule changes. TrainOrRest's internal Calendar is the source of truth; plan edits must go through the plan tool.",
            "If Watch push is configured, confirmed calendar edits are synced by the app to intervals.icu automatically after the user taps Apply changes. You cannot browse the user's intervals.icu account or manually upload files yourself, but do not say TrainOrRest lacks intervals.icu access when Watch push is configured.",
            "Training-load questions are explanation questions, not calendar-edit requests. In Vietnamese, 'tải tập', 'tải tuần', and 'tải tập tuần này' mean training load/workload. Answer from the Training load this week section; do not call a plan tool unless the user explicitly asks to change the calendar.",
            "Today is \(day(today, calendar: calendar)) (\(weekdayName(today, calendar: calendar))). Timezone: \(calendar.timeZone.identifier).",
            "Every tool date must be an absolute local calendar date formatted YYYY-MM-DD. Resolve relative wording like 'tomorrow' or 'Saturday' against today's date yourself; never pass relative text to a tool.",
            "For move requests, date is the source day that already has the workout and detail is the target day to move it to. The target day is normally empty and may be a rest/unavailable day; user intent overrides availability for one-off calendar edits. Do not set date to the empty target. If the user only names a target day but not which existing workout to move, ask which workout/date to move.",
            "For create requests, date is the free target day and workout is required. The free date may be a normal rest/unavailable day if the user explicitly wants to add a workout there. Use create only when adding a new workout rather than moving an existing one.",
            "If a plan tool call is rejected for missing or malformed fields, fix the JSON and call the tool again immediately. Do not ask the user to confirm the tool schema or JSON format.",
            "You may create easy, long, tempo, and interval workouts. A race distance or target time can be context for a training request: for example, ‘create a workout to help me run a half marathon under 1:50’ means create a safe non-race workout, not a goal change or race workout. Use the stated training day; if no day is stated, ask which day to schedule it. You cannot create or edit a race workout, and you cannot change the goal."
        ]

        let goal = try PlanStore.activeGoal(in: context)?.spec
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        lines += personalSettingsSection()
        lines += watchPushSection()
        lines += goalSection(goal: goal, fitness: fitness, today: today, calendar: calendar)
        lines += try trainingLoadSection(in: context, today: today, calendar: calendar, fitness: fitness)
        lines += try planSection(in: context, today: today, calendar: calendar)
        lines += try activitySection(in: context, today: today, calendar: calendar)
        lines += try readinessSection(in: context, today: today, calendar: calendar)
        lines += try freshnessSection(in: context)

        let text = lines.joined(separator: "\n")
        return text.count <= maxCharacters ? text : String(text.prefix(maxCharacters))
    }

    private static func personalSettingsSection() -> [String] {
        let settings = PersonalCoachSettings.current
        guard !settings.isEmpty else { return ["Personal coach settings: none set."] }
        return ["Personal coach settings. Use this stable user profile/preferences on every reply unless the user overrides it in the current message:\n\(settings)"]
    }

    private static func watchPushSection() -> [String] {
        let enabled = UserDefaults.standard.bool(forKey: WorkoutPushSettings.enabledKey)
        let athleteID = UserDefaults.standard.string(forKey: WorkoutPushSettings.athleteIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasKey = ((try? KeychainStore.load(account: KeychainStore.intervalsICUAccount)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let status: String
        if enabled, !athleteID.isEmpty, hasKey {
            status = "configured. Confirmed calendar edits sync to intervals.icu automatically after the user taps Apply changes."
        } else if enabled {
            status = "enabled but incomplete. Ask the user to finish Athlete ID/API key in Profile before expecting intervals.icu delivery."
        } else {
            status = "disabled. Calendar edits stay local until Watch push is enabled in Profile or the user uses Sync intervals.icu manually after configuration."
        }
        return ["Watch push / intervals.icu: \(status)"]
    }

    private static func goalSection(
        goal: GoalSpec?, fitness: FitnessProfile?, today: Date, calendar: Calendar
    ) -> [String] {
        guard let goal else { return ["Goal: none set."] }
        var lines = [
            "Goal: \(goal.distance.displayName) in \(Formatters.duration(goal.targetTimeSeconds)) on \(day(goal.raceDate, calendar: calendar)).",
            "Availability: \(goal.availableDays.sorted().map(\.shortName).joined(separator: ", ")); long run \(goal.longRunDay.shortName)."
        ]
        if let fitness {
            let assessment = FeasibilityCheck.assess(goal: goal, fitness: fitness, today: today, calendar: calendar)
            lines.append(String(
                format: "Fitness: VDOT %.1f, %.0f km/week, longest recent %.1f km; goal feasibility %@.",
                fitness.vdot, fitness.weeklyVolumeKm, fitness.longestRecentRunKm, assessment.verdict.rawValue
            ))
        } else {
            lines.append("Fitness: not enough recent run history.")
        }
        return lines
    }

    private static func planSection(in context: ModelContext, today: Date, calendar: Calendar) throws -> [String] {
        let dayStart = calendar.startOfDay(for: today)
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))
        guard !workouts.isEmpty else { return ["Plan: none generated."] }
        let end = calendar.date(byAdding: .day, value: 14, to: dayStart) ?? dayStart
        let upcoming = workouts.filter { $0.date >= dayStart && $0.date < end }
        var lines = ["Plan next 14 days:"]
        lines += upcoming.prefix(12).map { workout in
            "- \(day(workout.date, calendar: calendar)): \(workout.kind?.displayName ?? workout.kindRaw), \(String(format: "%.1f", workout.distanceKm)) km, \(workout.details)"
        }
        return lines
    }

    private static func trainingLoadSection(
        in context: ModelContext,
        today: Date,
        calendar: Calendar,
        fitness: FitnessProfile?
    ) throws -> [String] {
        let dayStart = calendar.startOfDay(for: today)
        let weekStart = PlanGenerator.mondayOfWeek(containing: dayStart, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? dayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }

        let completed = try context.fetch(FetchDescriptor<CompletedActivity>(
            predicate: #Predicate { $0.date >= weekStart && $0.date < weekEnd },
            sortBy: [SortDescriptor(\.date)]
        ))
        let completedLoad = completed.reduce(0) { total, activity in
            total + TrainingLoad.sessionLoad(
                durationSeconds: activity.durationSeconds,
                avgPaceSecondsPerKm: activity.avgPaceSecondsPerKm,
                paces: paces
            )
        }
        let completedKm = completed.reduce(0) { $0 + (($1.distanceMeters ?? 0) / 1000) }
        let completedMinutes = completed.reduce(0) { $0 + $1.durationSeconds } / 60

        let planned = try context.fetch(FetchDescriptor<PlannedWorkout>(
            predicate: #Predicate { $0.date >= weekStart && $0.date < weekEnd },
            sortBy: [SortDescriptor(\.date)]
        ))
        let futurePlanned = planned.filter { $0.date >= tomorrowStart && $0.status == .planned }
        let plannedRemainingLoad = futurePlanned.compactMap { $0.expectedDurationSeconds }.reduce(0) { total, seconds in
            total + TrainingLoad.sessionLoad(durationSeconds: seconds, avgPaceSecondsPerKm: nil, paces: nil)
        }
        let plannedRemainingKm = futurePlanned.reduce(0) { $0 + $1.distanceKm }
        let plannedRemainingMinutes = futurePlanned.compactMap(\.expectedDurationSeconds).reduce(0, +) / 60

        var lines = [
            "Training load this week (local week \(day(weekStart, calendar: calendar))...\(day(weekEnd, calendar: calendar))): completed load \(wholeNumber(completedLoad)), \(String(format: "%.1f", completedKm)) km, \(wholeNumber(completedMinutes)) min across \(completed.count) run(s); planned remaining load \(wholeNumber(plannedRemainingLoad)), \(String(format: "%.1f", plannedRemainingKm)) km, \(wholeNumber(plannedRemainingMinutes)) min across \(futurePlanned.count) workout(s); projected total load \(wholeNumber(completedLoad + plannedRemainingLoad))."
        ]
        if let readiness = try todayReadiness(in: context, today: today, calendar: calendar), let acwr = readiness.acuteChronicRatio {
            lines.append(String(format: "Training load trend: ACWR %.2f.", acwr))
        } else {
            lines.append("Training load trend: ACWR unavailable until enough recent history is synced.")
        }
        return lines
    }

    private static func activitySection(in context: ModelContext, today: Date, calendar: Calendar) throws -> [String] {
        let start = calendar.date(byAdding: .day, value: -14, to: today) ?? .distantPast
        let activities = try context.fetch(FetchDescriptor<CompletedActivity>(
            predicate: #Predicate { $0.date >= start },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
        guard !activities.isEmpty else { return ["Last 14 days: no synced runs."] }
        var lines = ["Last 14 days runs:"]
        lines += activities.prefix(10).map {
            "- \(day($0.date, calendar: calendar)): \(Formatters.kilometers($0.distanceMeters)), \(Formatters.pace($0.avgPaceSecondsPerKm)), avg HR \(Formatters.heartRate($0.avgHeartRate))"
        }
        return lines
    }

    private static func readinessSection(in context: ModelContext, today: Date, calendar: Calendar) throws -> [String] {
        guard let readiness = try todayReadiness(in: context, today: today, calendar: calendar) else { return ["Readiness today: not computed."] }
        let reasons = readiness.reasons.isEmpty ? "no flags" : readiness.reasons.joined(separator: "; ")
        return ["Readiness today: \(readiness.verdict.rawValue), \(reasons)."]
    }

    private static func todayReadiness(in context: ModelContext, today: Date, calendar: Calendar) throws -> DailyReadiness? {
        let dayStart = calendar.startOfDay(for: today)
        var descriptor = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.date == dayStart })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func wholeNumber(_ value: Double) -> String {
        String(format: "%.0f", value.rounded())
    }

    private static func freshnessSection(in context: ModelContext) throws -> [String] {
        let states = try context.fetch(FetchDescriptor<SyncState>())
        guard let date = states.compactMap(\.lastSyncAt).max() else { return ["Data freshness: never synced."] }
        return ["Data freshness: \(date.formatted(date: .abbreviated, time: .shortened))."]
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar: calendar, format: "yyyy-MM-dd").string(from: date)
    }

    static func weekdayName(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar: calendar, format: "EEEE").string(from: date)
    }

    private static func formatter(calendar: Calendar, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
