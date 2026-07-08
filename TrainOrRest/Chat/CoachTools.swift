import Foundation
import SwiftData

struct PlanAdjustmentProposal: Codable, Equatable {
    var changes: [Change]

    struct Change: Codable, Equatable {
        enum Action: String, Codable {
            case swap, downgrade, rest, move
        }

        var date: String
        var action: Action
        var detail: String?
    }
}

struct AppliedAdjustment: Equatable {
    var summary: String
}

@MainActor
enum CoachTools {
    static let toolName = "propose_plan_adjustment"

    static var tool: ClaudeTool {
        ClaudeTool(
            name: toolName,
            description: "Propose safe edits to the user's planned workouts. The app validates every edit before applying it.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "changes": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "date": .object(["type": .string("string"), "description": .string("Workout date as YYYY-MM-DD")]),
                                "action": .object(["type": .string("string"), "enum": .array(["swap", "downgrade", "rest", "move"].map(JSONValue.string))]),
                                "detail": .object(["type": .string("string"), "description": .string("Target date as YYYY-MM-DD for swap or move")])
                            ]),
                            "required": .array(["date", "action"].map(JSONValue.string))
                        ])
                    ])
                ]),
                "required": .array([.string("changes")])
            ])
        )
    }

    static func apply(
        proposal: PlanAdjustmentProposal,
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> AppliedAdjustment {
        var spec = try currentPlanSpec(in: context, today: today, calendar: calendar)
        let fitness = try PlanStore.currentFitness(in: context, today: today, calendar: calendar)
        let paces = fitness.map { VDOTTable.trainingPaces(vdot: $0.vdot) }

        var summaries: [String] = []
        for change in proposal.changes {
            let date = try parseDay(change.date, calendar: calendar)
            guard date >= calendar.startOfDay(for: today) else {
                throw ValidationError("Cannot edit past workouts.")
            }
            summaries.append(try apply(change, date: date, paces: paces, to: &spec, calendar: calendar))
        }

        let peakCap = fitness.map { max($0.weeklyVolumeKm * 1.35, $0.longestRecentRunKm * 2) }
        let issues = PlanValidator.validate(spec, calendar: calendar, peakCapKm: peakCap)
        guard issues.isEmpty else {
            throw ValidationError(issues.map(\.message).joined(separator: "; "))
        }

        try persist(spec, in: context, from: today, calendar: calendar)
        try context.save()
        return AppliedAdjustment(summary: summaries.joined(separator: "; "))
    }

    private static func apply(
        _ change: PlanAdjustmentProposal.Change,
        date: Date,
        paces: TrainingPaces?,
        to spec: inout TrainingPlanSpec,
        calendar: Calendar
    ) throws -> String {
        guard let location = locate(date, in: spec) else { throw ValidationError("No workout on \(change.date).") }
        let workout = spec.weeks[location.week].workouts[location.workout]
        guard workout.kind != .race else { throw ValidationError("Race day cannot be edited.") }

        switch change.action {
        case .rest:
            spec.weeks[location.week].workouts.remove(at: location.workout)
            return "Rested \(change.date)"
        case .downgrade:
            let structure = WorkoutStructure.run(distanceKm: workout.distanceKm, paceBand: paces?.easy)
            spec.weeks[location.week].workouts[location.workout] = PlannedWorkoutSpec(
                date: date, kind: .easy, distanceKm: workout.distanceKm,
                paceBand: paces?.easy, details: WorkoutProse.details(for: .easy, structure: structure),
                structure: structure
            )
            return "Downgraded \(change.date) to easy"
        case .move:
            let target = try targetDay(change.detail, calendar: calendar)
            spec.weeks[location.week].workouts[location.workout].date = target
            return "Moved \(change.date) to \(CoachContextBuilder.day(target, calendar: calendar))"
        case .swap:
            let target = try targetDay(change.detail, calendar: calendar)
            guard let other = locate(target, in: spec) else { throw ValidationError("No workout on target date.") }
            spec.weeks[location.week].workouts[location.workout].date = target
            spec.weeks[other.week].workouts[other.workout].date = date
            return "Swapped \(change.date) with \(CoachContextBuilder.day(target, calendar: calendar))"
        }
    }

    private static func currentPlanSpec(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) throws -> TrainingPlanSpec {
        guard let goal = try PlanStore.activeGoal(in: context)?.spec,
              let plan = try PlanStore.activePlan(in: context) else {
            throw ValidationError("No active plan.")
        }
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>(sortBy: [SortDescriptor(\.date)]))
        let weeks = plan.weekPhasesRaw.indices.map { index in
            let phase = TrainingPhase(rawValue: plan.weekPhasesRaw[index]) ?? .base
            let start = calendar.date(byAdding: .day, value: index * 7, to: PlanGenerator.mondayOfWeek(containing: plan.anchorDate, calendar: calendar))!
            let rows = workouts.filter { $0.weekIndex == index }.compactMap(toSpec)
            return WeekPlan(
                startDate: start, index: index, phase: phase,
                isDownWeek: plan.weekIsDown[index],
                isPartial: index == 0 && !calendar.isDate(plan.anchorDate, inSameDayAs: start),
                targetVolumeKm: plan.weekTargetVolumesKm[index],
                workouts: rows
            )
        }
        return TrainingPlanSpec(goal: goal, anchorDate: calendar.startOfDay(for: today), weeks: weeks)
    }

    private static func persist(
        _ spec: TrainingPlanSpec,
        in context: ModelContext,
        from today: Date,
        calendar: Calendar
    ) throws {
        let dayStart = calendar.startOfDay(for: today)
        let rows = try context.fetch(FetchDescriptor<PlannedWorkout>())
        for row in rows where row.date >= dayStart && row.status == .planned && !row.manuallyOverridden {
            context.delete(row)
        }
        guard let plan = try PlanStore.activePlan(in: context) else { return }
        for week in spec.weeks {
            for workout in week.workouts where workout.date >= dayStart {
                let row = PlannedWorkout(spec: workout, weekIndex: week.index, phase: week.phase)
                row.manuallyOverridden = true
                row.plan = plan
                context.insert(row)
            }
        }
        plan.generatedAt = today
    }

    private static func toSpec(_ row: PlannedWorkout) -> PlannedWorkoutSpec? {
        guard let kind = row.kind else { return nil }
        return PlannedWorkoutSpec(
            date: row.date, kind: kind, distanceKm: row.distanceKm,
            paceBand: row.paceBand, details: row.details, structure: row.structure
        )
    }

    private static func locate(_ date: Date, in spec: TrainingPlanSpec) -> (week: Int, workout: Int)? {
        for weekIndex in spec.weeks.indices {
            if let workoutIndex = spec.weeks[weekIndex].workouts.firstIndex(where: { $0.date == date }) {
                return (weekIndex, workoutIndex)
            }
        }
        return nil
    }

    private static func targetDay(_ value: String?, calendar: Calendar) throws -> Date {
        guard let value else { throw ValidationError("Target date is required.") }
        return try parseDay(value, calendar: calendar)
    }

    static func parseDay(_ value: String, calendar: Calendar) throws -> Date {
        var format = Date.FormatStyle().year().month(.twoDigits).day(.twoDigits)
        format.timeZone = calendar.timeZone
        guard let date = try? Date(value, strategy: format) else { throw ValidationError("Invalid date \(value).") }
        return calendar.startOfDay(for: date)
    }

    struct ValidationError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
