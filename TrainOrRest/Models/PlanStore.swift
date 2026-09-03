import Foundation
import SwiftData

/// Thin mapping layer between the pure plan engine and SwiftData: feeds the
/// engine from stored activities and persists its value-type output. All the
/// logic lives in `PlanEngine/`; this file only fetches, maps, and saves.
@MainActor
enum PlanStore {
    // MARK: - Engine inputs

    /// Runs on or after `start`. The estimator never looks further back than
    /// its history window, so older rows stay on disk.
    static func runSamples(in context: ModelContext, since start: Date) throws -> [RunSample] {
        let descriptor = FetchDescriptor<CompletedActivity>(predicate: #Predicate { $0.date >= start })
        return try context.fetch(descriptor).compactMap { activity in
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
        let start = calendar.date(
            byAdding: .day,
            value: -FitnessEstimator.historyWindowWeeks * 7,
            to: calendar.startOfDay(for: today)
        ) ?? .distantPast
        return FitnessEstimator.estimate(
            samples: try runSamples(in: context, since: start), today: today, calendar: calendar
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
        var insertedWorkouts: [PlannedWorkout] = []
        for week in planSpec.weeks {
            for workoutSpec in week.workouts {
                let workout = PlannedWorkout(spec: workoutSpec, weekIndex: week.index, phase: week.phase)
                workout.plan = plan
                context.insert(workout)
                insertedWorkouts.append(workout)
            }
        }
        try ShoeAssignmentService.assignAutomaticShoes(to: insertedWorkouts, in: context)
        try context.save()
    }

    // MARK: - Activity auto-matching

    /// Marks planned workouts done when a synced activity matches them.
    /// Only touches automatic state — manual done/skip decisions stay.
    static func autoMatch(in context: ModelContext, calendar: Calendar) throws {
        let workouts = try context.fetch(FetchDescriptor<PlannedWorkout>())
        let candidates = workouts.filter { $0.status == .planned && !$0.manuallyOverridden }
        guard !candidates.isEmpty else { return }

        // Matching is same-day, so only activities inside the candidates'
        // date span can pair; older history stays on disk.
        let firstDay = calendar.startOfDay(for: candidates.map(\.date).min()!)
        let lastDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: candidates.map(\.date).max()!))!
        let activities = try context.fetch(FetchDescriptor<CompletedActivity>(
            predicate: #Predicate { $0.date >= firstDay && $0.date < lastDay }
        ))
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
                if let activity = activities.first(where: { $0.hkUUID == activityID }),
                   activity.shoeAssignmentSource != .manual,
                   activity.shoeAssignmentSource != .syncedProvider {
                    activity.shoeID = workout.shoeID
                    activity.shoeAssignmentSource = workout.shoeID == nil ? .none : workout.shoeAssignmentSource
                    try ShoeMileageService.syncMileage(for: activity, in: context)
                }
            }
        }
        try context.save()
    }
}
