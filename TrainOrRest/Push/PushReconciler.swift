import Foundation

struct WorkoutPushPlan: Equatable {
    var toUpsert: [IntervalsWorkoutEvent]
    var toDelete: [Int]
}

enum PushReconciler {
    static let externalIDPrefix = "trainorrest-"
    static let windowDays = 7

    static func desiredEvents(
        from workouts: [PlannedWorkout],
        today: Date,
        calendar: Calendar
    ) -> [IntervalsWorkoutEvent] {
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: windowDays, to: start) ?? start
        return workouts.compactMap { workout in
            guard workout.date >= start,
                  workout.date < end,
                  workout.status == .planned,
                  !workout.structure.isEmpty else { return nil }
            return WorkoutDSL.event(for: workout, calendar: calendar)
        }
    }

    static func reconcile(
        desiredEvents: [IntervalsWorkoutEvent],
        remoteEvents: [RemoteWorkoutEvent]
    ) -> WorkoutPushPlan {
        let desiredIDs = Set(desiredEvents.map(\.externalID))
        let toDelete = remoteEvents.compactMap { event -> Int? in
            guard let externalID = event.externalID,
                  externalID.hasPrefix(externalIDPrefix),
                  !desiredIDs.contains(externalID) else { return nil }
            return event.id
        }
        return WorkoutPushPlan(toUpsert: desiredEvents, toDelete: toDelete)
    }
}
