import Foundation
import SwiftData

struct EvidenceSelection: Equatable {
    var readinessSnapshot: Bool
    var weekPlan: Bool
    var workout: WorkoutContextSelection?
    var hasPhoto: Bool

    init(
        readinessSnapshot: Bool = true,
        weekPlan: Bool = true,
        workout: WorkoutContextSelection? = nil,
        hasPhoto: Bool = false
    ) {
        self.readinessSnapshot = readinessSnapshot
        self.weekPlan = weekPlan
        self.workout = workout
        self.hasPhoto = hasPhoto
    }
}

struct GroundingSnapshot: Equatable {
    let id: UUID
    let timestamp: Date
    let readinessVersion: String
    let planVersion: String
    let evidence: EvidenceSelection
    let summary: String

    var footnoteLine: String {
        var parts = ["Based on \(Self.footnoteTimeFormatter.string(from: timestamp))"]
        if evidence.readinessSnapshot {
            parts.append("Readiness")
        }
        if evidence.weekPlan {
            parts.append("This week")
        }
        if evidence.workout != nil {
            parts.append(workoutFootnoteLabel)
        }
        if evidence.hasPhoto {
            parts.append("Photo")
        }
        if parts.count == 1 {
            parts.append("No evidence")
        }
        return parts.joined(separator: " · ")
    }

    private var workoutFootnoteLabel: String {
        guard let line = summary.components(separatedBy: "\n").first(where: { $0.hasPrefix("Workout: ") }) else {
            return "Workout"
        }
        let body = line.replacingOccurrences(of: "Workout: ", with: "")
        guard let firstWord = body.split(separator: " ").first else { return "Workout" }
        return "\(firstWord) workout"
    }

    private static let footnoteTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

@MainActor
enum CoachGrounding {
    static func snapshot(
        evidence: EvidenceSelection,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> GroundingSnapshot {
        let readiness = try todayReadiness(in: context, today: today, calendar: calendar)
        let plan = try PlanStore.activePlan(in: context)
        let summary = try GroundingSummaryEncoder.summary(
            evidence: evidence,
            readiness: readiness,
            plan: plan,
            plannedWorkouts: plannedWorkouts(in: context, today: today, calendar: calendar),
            workoutSummary: workoutSummary(for: evidence.workout, in: context, calendar: calendar),
            today: today,
            calendar: calendar
        )
        return GroundingSnapshot(
            id: UUID(),
            timestamp: today,
            readinessVersion: readiness.map { isoString($0.computedAt) } ?? "none",
            planVersion: plan.map { isoString($0.generatedAt) } ?? "none",
            evidence: evidence,
            summary: summary
        )
    }

    private static func todayReadiness(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> DailyReadiness? {
        let dayStart = calendar.startOfDay(for: today)
        return try context.fetch(FetchDescriptor<DailyReadiness>()).first {
            calendar.isDate($0.date, inSameDayAs: dayStart)
        }
    }

    private static func plannedWorkouts(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> [PlannedWorkout] {
        let dayStart = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 7, to: dayStart) ?? dayStart
        return try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)])).filter {
            $0.date >= dayStart && $0.date < end
        }
    }

    private static func workoutSummary(
        for selection: WorkoutContextSelection?,
        in context: ModelContext,
        calendar: Calendar
    ) throws -> String? {
        switch selection {
        case .planned(let uuid):
            guard let workout = try context.fetch(FetchDescriptor<PlannedWorkout>()).first(where: { $0.uuid == uuid }) else {
                return "selected workout unavailable"
            }
            return "\(weekday(workout.date, calendar: calendar)) planned \(workout.kind?.displayName ?? workout.kindRaw), \(oneDecimal(workout.distanceKm)) km"
        case .completed(let uuid):
            guard let activity = try context.fetch(FetchDescriptor<CompletedActivity>()).first(where: { $0.hkUUID == uuid }) else {
                return "selected workout unavailable"
            }
            let distance = activity.distanceMeters.map { oneDecimal($0 / 1000) + " km" } ?? "distance unknown"
            return "\(weekday(activity.date, calendar: calendar)) completed run, \(distance)"
        case nil:
            return nil
        }
    }

    fileprivate nonisolated static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter.grounding.string(from: date)
    }

    fileprivate nonisolated static func weekday(_ date: Date, calendar: Calendar) -> String {
        dateString(date, calendar: calendar, format: "EEE")
    }

    fileprivate nonisolated static func day(_ date: Date, calendar: Calendar) -> String {
        dateString(date, calendar: calendar, format: "yyyy-MM-dd")
    }

    fileprivate nonisolated static func dateString(_ date: Date, calendar: Calendar, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    fileprivate nonisolated static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private enum GroundingSummaryEncoder {
    static func summary(
        evidence: EvidenceSelection,
        readiness: DailyReadiness?,
        plan: TrainingPlan?,
        plannedWorkouts: [PlannedWorkout],
        workoutSummary: String?,
        today: Date,
        calendar: Calendar
    ) throws -> String {
        var lines: [String] = []
        lines.append(readinessLine(evidence: evidence, readiness: readiness))
        lines.append(planLine(evidence: evidence, workouts: plannedWorkouts, today: today, calendar: calendar))
        if let workoutSummary {
            lines.append("Workout: \(workoutSummary).")
        } else if evidence.workout != nil {
            lines.append("Workout: selected workout unavailable.")
        }
        if evidence.hasPhoto {
            lines.append("Photo: attached; metadata stripped before send.")
        }
        let readinessVersion = readiness.map { CoachGrounding.isoString($0.computedAt) } ?? "none"
        let planVersion = plan.map { CoachGrounding.isoString($0.generatedAt) } ?? "none"
        lines.append("Versions: readiness \(readinessVersion); plan \(planVersion).")
        return lines.joined(separator: "\n")
    }

    private static func readinessLine(evidence: EvidenceSelection, readiness: DailyReadiness?) -> String {
        guard evidence.readinessSnapshot else { return "Readiness: not included." }
        guard let readiness else { return "Readiness: not computed." }

        var parts: [String] = []
        if let score = readiness.score {
            parts.append("score \(score)")
        }
        if !readiness.ruleIDsRaw.isEmpty {
            parts.append("rules \(readiness.ruleIDsRaw.joined(separator: ","))")
        }
        if !readiness.reasons.isEmpty {
            parts.append("reasons \(readiness.reasons.joined(separator: "; "))")
        } else {
            parts.append("reasons no flags")
        }

        let signals = signalSummary(readiness)
        if !signals.isEmpty {
            parts.append("signals \(signals)")
        }
        return "Readiness: \(readiness.verdict.rawValue) (\(parts.joined(separator: "; ")))."
    }

    private static func signalSummary(_ readiness: DailyReadiness) -> String {
        var signals: [String] = []
        if let sleep = readiness.sleepLastNight, let mean = readiness.sleepMean14 {
            signals.append("sleep \(CoachGrounding.oneDecimal(sleep))h vs \(CoachGrounding.oneDecimal(mean))h")
        }
        if let acwr = readiness.acuteChronicRatio {
            signals.append("ACWR \(CoachGrounding.oneDecimal(acwr))")
        }
        if let hrv7 = readiness.hrvMean7, let hrv28 = readiness.hrvMean28 {
            signals.append("HRV \(CoachGrounding.oneDecimal(hrv7)) vs \(CoachGrounding.oneDecimal(hrv28))")
        }
        if let rhr7 = readiness.rhrMean7, let rhr28 = readiness.rhrMean28 {
            signals.append("RHR \(CoachGrounding.oneDecimal(rhr7)) vs \(CoachGrounding.oneDecimal(rhr28))")
        }
        return signals.joined(separator: ", ")
    }

    private static func planLine(
        evidence: EvidenceSelection,
        workouts: [PlannedWorkout],
        today: Date,
        calendar: Calendar
    ) -> String {
        guard evidence.weekPlan else { return "Plan: not included." }
        let dayStart = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 6, to: dayStart) ?? dayStart
        let window = "\(CoachGrounding.day(dayStart, calendar: calendar))...\(CoachGrounding.day(end, calendar: calendar))"
        guard !workouts.isEmpty else { return "Plan: \(window); no workouts scheduled." }
        let entries = workouts.map {
            "\(CoachGrounding.weekday($0.date, calendar: calendar)) \($0.kind?.displayName ?? $0.kindRaw) \(CoachGrounding.oneDecimal($0.distanceKm)) km"
        }
        return "Plan: \(window); \(entries.joined(separator: "; "))."
    }
}

private extension ISO8601DateFormatter {
    static let grounding: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
