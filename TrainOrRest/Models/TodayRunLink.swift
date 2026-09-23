import Foundation

enum TodayRunLink: Equatable {
    case rest
    case pending(PlannedWorkout)
    case suggested(PlannedWorkout, CompletedActivity)
    case linked(PlannedWorkout, CompletedActivity)
    case doneWithoutRun(PlannedWorkout)
    case skipped(PlannedWorkout)
    case unplannedRun(CompletedActivity)

    static func resolve(workouts: [PlannedWorkout], activities: [CompletedActivity]) -> TodayRunLink {
        let orderedWorkouts = workouts.sorted {
            ($0.date, $0.uuid.uuidString) < ($1.date, $1.uuid.uuidString)
        }
        let linkedActivityIDs = Set(workouts.compactMap(\.matchedActivityUUID))
        let freeActivities = activities.filter { !linkedActivityIDs.contains($0.hkUUID) }
        let freeActivityRefs = freeActivities.map {
            WorkoutMatcher.ActivityRef(id: $0.hkUUID, date: $0.date, durationSeconds: $0.durationSeconds)
        }

        for workout in orderedWorkouts where workout.status == .planned {
            if let activityID = WorkoutMatcher.suggestion(for: workout.matcherRef, among: freeActivityRefs),
               let activity = freeActivities.first(where: { $0.hkUUID == activityID }) {
                return .suggested(workout, activity)
            }
        }
        if let workout = orderedWorkouts.first(where: { $0.status == .planned }) {
            return .pending(workout)
        }
        if let workout = orderedWorkouts.first(where: { workout in
            workout.status == .done && activities.contains(where: { $0.hkUUID == workout.matchedActivityUUID })
        }), let activity = activities.first(where: { $0.hkUUID == workout.matchedActivityUUID }) {
            return .linked(workout, activity)
        }
        if let workout = orderedWorkouts.first(where: { $0.status == .done }) {
            return .doneWithoutRun(workout)
        }
        if let workout = orderedWorkouts.first(where: { $0.status == .skipped }) {
            return .skipped(workout)
        }
        if workouts.isEmpty,
           let activity = activities.max(by: { ($0.date, $0.hkUUID.uuidString) < ($1.date, $1.hkUUID.uuidString) }) {
            return .unplannedRun(activity)
        }
        return .rest
    }

    static func == (lhs: TodayRunLink, rhs: TodayRunLink) -> Bool {
        switch (lhs, rhs) {
        case (.rest, .rest):
            true
        case let (.pending(left), .pending(right)),
             let (.doneWithoutRun(left), .doneWithoutRun(right)),
             let (.skipped(left), .skipped(right)):
            left.uuid == right.uuid
        case let (.suggested(leftWorkout, leftActivity), .suggested(rightWorkout, rightActivity)),
             let (.linked(leftWorkout, leftActivity), .linked(rightWorkout, rightActivity)):
            leftWorkout.uuid == rightWorkout.uuid && leftActivity.hkUUID == rightActivity.hkUUID
        case let (.unplannedRun(left), .unplannedRun(right)):
            left.hkUUID == right.hkUUID
        default:
            false
        }
    }
}
