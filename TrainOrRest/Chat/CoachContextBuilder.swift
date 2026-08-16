import Foundation
import SwiftData

@MainActor
enum CoachContextBuilder {
    static let maxCharacters = 8000

    static func build(in context: ModelContext, today: Date, calendar: Calendar) throws -> String {
        var lines: [String] = [
            "You are TrainOrRest, a cautious running coach. Explain decisions from the user's actual data.",
            "Use plan tools only for schedule changes. Never claim a plan edit was applied unless a tool result confirms it.",
            "Today is \(day(today, calendar: calendar)) (\(weekdayName(today, calendar: calendar))). Timezone: \(calendar.timeZone.identifier).",
            "Every tool date must be an absolute local calendar date formatted YYYY-MM-DD. Resolve relative wording like 'tomorrow' or 'Saturday' against today's date yourself; never pass relative text to a tool.",
            "You may create easy, long, tempo, and interval workouts. A race distance or target time can be context for a training request: for example, ‘create a workout to help me run a half marathon under 1:50’ means create a safe non-race workout, not a goal change or race workout. Use the stated training day; if no day is stated, ask which day to schedule it. You cannot create or edit a race workout, and you cannot change the goal."
        ]

        let goal = try PlanStore.activeGoal(in: context)?.spec
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        lines += personalSettingsSection()
        lines += goalSection(goal: goal, fitness: fitness, today: today, calendar: calendar)
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
        let dayStart = calendar.startOfDay(for: today)
        var descriptor = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.date == dayStart })
        descriptor.fetchLimit = 1
        guard let readiness = try context.fetch(descriptor).first else { return ["Readiness today: not computed."] }
        let reasons = readiness.reasons.isEmpty ? "no flags" : readiness.reasons.joined(separator: "; ")
        return ["Readiness today: \(readiness.verdict.rawValue), \(reasons)."]
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
