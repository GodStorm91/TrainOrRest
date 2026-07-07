import Foundation

/// Matches completed activities to planned workouts. Pure and deterministic:
/// same-day candidates, duration within tolerance preferred, single-run-day
/// fallback. Each activity matches at most one workout.
enum WorkoutMatcher {
    /// Accepted relative deviation between actual and expected duration.
    static let durationTolerance = 0.4

    struct PlannedRef: Equatable {
        var id: UUID
        var date: Date
        /// Estimated duration from distance × mid pace; nil when the workout
        /// has no pace band to estimate from.
        var expectedDurationSeconds: Double?
    }

    struct ActivityRef: Equatable {
        var id: UUID
        var date: Date
        var durationSeconds: Double
    }

    /// Returns planned-workout ID → activity ID assignments.
    static func matches(
        planned: [PlannedRef],
        activities: [ActivityRef],
        calendar: Calendar
    ) -> [UUID: UUID] {
        var assignments: [UUID: UUID] = [:]
        var usedActivities: Set<UUID> = []

        let plannedByDay = Dictionary(grouping: planned) { calendar.startOfDay(for: $0.date) }
        let activitiesByDay = Dictionary(grouping: activities) { calendar.startOfDay(for: $0.date) }

        for (day, dayPlanned) in plannedByDay.sorted(by: { $0.key < $1.key }) {
            let candidates = (activitiesByDay[day] ?? []).sorted { $0.durationSeconds < $1.durationSeconds }
            guard !candidates.isEmpty else { continue }
            let orderedPlanned = dayPlanned.sorted {
                ($0.expectedDurationSeconds ?? 0, $0.id.uuidString) < ($1.expectedDurationSeconds ?? 0, $1.id.uuidString)
            }

            // First pass: closest duration within tolerance.
            for workout in orderedPlanned {
                guard let expected = workout.expectedDurationSeconds, expected > 0 else { continue }
                let best = candidates
                    .filter { !usedActivities.contains($0.id) }
                    .map { (activity: $0, deviation: abs($0.durationSeconds - expected) / expected) }
                    .filter { $0.deviation <= durationTolerance }
                    .min { ($0.deviation, $0.activity.id.uuidString) < ($1.deviation, $1.activity.id.uuidString) }
                if let best {
                    assignments[workout.id] = best.activity.id
                    usedActivities.insert(best.activity.id)
                }
            }

            // Fallback: a lone run on a day with one unmatched workout counts.
            let unmatchedPlanned = orderedPlanned.filter { assignments[$0.id] == nil }
            let freeActivities = candidates.filter { !usedActivities.contains($0.id) }
            if unmatchedPlanned.count == 1, freeActivities.count == 1,
               let workout = unmatchedPlanned.first, let activity = freeActivities.first {
                assignments[workout.id] = activity.id
                usedActivities.insert(activity.id)
            }
        }
        return assignments
    }
}
