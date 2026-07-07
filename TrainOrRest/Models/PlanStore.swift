import Foundation
import SwiftData

/// Thin mapping layer between the pure plan engine and SwiftData: feeds the
/// engine from stored activities and persists its value-type output. All the
/// logic lives in `PlanEngine/`; this file only fetches, maps, and saves.
@MainActor
enum PlanStore {
    // MARK: - Engine inputs

    static func runSamples(in context: ModelContext) throws -> [RunSample] {
        try context.fetch(FetchDescriptor<CompletedActivity>()).compactMap { activity in
            guard let meters = activity.distanceMeters, meters > 0 else { return nil }
            return RunSample(
                date: activity.date,
                distanceKm: meters / 1000,
                durationSeconds: activity.durationSeconds
            )
        }
    }

    static func currentFitness(
        in context: ModelContext, today: Date, calendar: Calendar
    ) throws -> FitnessProfile? {
        FitnessEstimator.estimate(
            samples: try runSamples(in: context), today: today, calendar: calendar
        )
    }

    // MARK: - Goal / plan lifecycle

    static func activeGoal(in context: ModelContext) throws -> Goal? {
        try context.fetch(FetchDescriptor<Goal>()).first
    }

    static func activePlan(in context: ModelContext) throws -> TrainingPlan? {
        try context.fetch(FetchDescriptor<TrainingPlan>()).first
    }

    /// Replaces the active goal (and its plan) with a freshly generated one.
    static func replaceGoal(
        spec: GoalSpec,
        fitness: FitnessProfile,
        today: Date,
        calendar: Calendar,
        in context: ModelContext
    ) throws {
        for goal in try context.fetch(FetchDescriptor<Goal>()) {
            context.delete(goal)
        }
        for plan in try context.fetch(FetchDescriptor<TrainingPlan>()) {
            context.delete(plan) // cascades to workouts
        }

        context.insert(Goal(spec: spec, createdAt: today))

        let planSpec = PlanGenerator.generate(goal: spec, fitness: fitness, today: today, calendar: calendar)
        let plan = TrainingPlan(spec: planSpec, generatedAt: today)
        context.insert(plan)
        for week in planSpec.weeks {
            for workoutSpec in week.workouts {
                let workout = PlannedWorkout(spec: workoutSpec, weekIndex: week.index, phase: week.phase)
                workout.plan = plan
                context.insert(workout)
            }
        }
        try context.save()
    }

    // MARK: - Activity auto-matching

    /// Marks planned workouts done when a synced activity matches them.
    /// Only touches automatic state — manual done/skip decisions stay.
    static func autoMatch(in context: ModelContext, calendar: Calendar) throws {
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        let candidates = workouts.filter { $0.status == .planned && !$0.manuallyOverridden }
        guard !candidates.isEmpty else { return }

        let activities = try context.fetch(FetchDescriptor<CompletedActivity>())
        let alreadyMatched = Set(workouts.compactMap(\.matchedActivityUUID))

        let plannedRefs = candidates.map {
            WorkoutMatcher.PlannedRef(
                id: $0.uuid, date: $0.date, expectedDurationSeconds: $0.expectedDurationSeconds
            )
        }
        let activityRefs = activities
            .filter { !alreadyMatched.contains($0.hkUUID) }
            .map {
                WorkoutMatcher.ActivityRef(
                    id: $0.hkUUID, date: $0.date, durationSeconds: $0.durationSeconds
                )
            }

        let matches = WorkoutMatcher.matches(planned: plannedRefs, activities: activityRefs, calendar: calendar)
        guard !matches.isEmpty else { return }
        for workout in candidates {
            if let activityID = matches[workout.uuid] {
                workout.status = .done
                workout.matchedActivityUUID = activityID
            }
        }
        try context.save()
    }
}
