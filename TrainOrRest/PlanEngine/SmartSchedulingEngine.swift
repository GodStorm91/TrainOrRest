import Foundation

struct SmartSchedulingPreferences: Equatable {
    var preferredTime: PreferredTrainingTime
    var earliestStartMinutes: Int
    var latestFinishMinutes: Int
    var bufferBeforeMinutes: Int
    var bufferAfterMinutes: Int
}

struct SchedulingRequest {
    var workout: PlannedWorkout
    var candidateDates: [Date]
    var currentTrainingWeek: Int
    var surroundingWorkouts: [PlannedWorkout]
    var userPreferences: SmartSchedulingPreferences
    var availability: [DayAvailability]
    var timezone: TimeZone
    var plan: TrainingPlan
    var goal: GoalSpec
}

struct SchedulingCandidate: Identifiable, Equatable {
    var id: String { "\(workoutID.uuidString)-\(startTime.timeIntervalSince1970)" }
    var workoutID: UUID
    var date: Date
    var startTime: Date
    var endTime: Date
    var score: Int
    var reasons: [String]
    var conflicts: [String]

    var isValid: Bool { conflicts.isEmpty }
}

struct WeekScheduleFit: Equatable {
    enum Status: String {
        case fitsWell
        case needsScheduling
        case scheduleConflict
    }

    var scheduledWorkouts: Int
    var unscheduledWorkouts: Int
    var conflictingWorkouts: Int
    var availableValidSlots: Int
    var status: Status
}

struct SmartSchedulingEngine {
    private let calendar: Calendar
    private let validation: ScheduleMoveValidationService

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.validation = ScheduleMoveValidationService(calendar: calendar)
    }

    func candidates(for request: SchedulingRequest, limit: Int = 3) -> [SchedulingCandidate] {
        guard !request.workout.isScheduleLocked else { return [] }
        let duration = requiredWorkoutDurationSeconds(for: request.workout)
        let requiredSeconds = duration
            + Double(request.userPreferences.bufferBeforeMinutes * 60)
            + Double(request.userPreferences.bufferAfterMinutes * 60)
        let daysByDate = Dictionary(uniqueKeysWithValues: request.availability.map { (calendar.startOfDay(for: $0.date), $0) })

        var output: [SchedulingCandidate] = []
        for candidateDate in request.candidateDates {
            let day = calendar.startOfDay(for: candidateDate)
            guard let availability = daysByDate[day] else { continue }
            let validationResult = validation.validate(
                workout: request.workout,
                targetDate: candidateDate,
                allWorkouts: request.surroundingWorkouts,
                plan: request.plan,
                goal: request.goal
            )
            guard validationResult.result == .safeAutomatic || validationResult.result == .sameDayTimeOnly else {
                continue
            }
            for window in availability.availableWindows where window.durationMinutes * 60 >= Int(requiredSeconds) {
                guard let start = bufferedStart(in: window, preferences: request.userPreferences, durationSeconds: duration),
                      let end = calendar.date(byAdding: .second, value: Int(duration), to: start) else { continue }
                let candidate = candidate(
                    workout: request.workout,
                    day: day,
                    start: start,
                    end: end,
                    availabilityWindow: window,
                    preferences: request.userPreferences,
                    validation: validationResult
                )
                if candidate.isValid {
                    output.append(candidate)
                }
            }
        }
        return output
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.startTime < rhs.startTime
            }
            .prefix(limit)
            .map { $0 }
    }

    func weekFit(workouts: [PlannedWorkout], availability: [DayAvailability], requestFactory: (PlannedWorkout) -> SchedulingRequest?) -> WeekScheduleFit {
        var scheduled = 0
        var unscheduled = 0
        var conflicts = 0
        var validSlots = 0
        for workout in workouts {
            if isTimed(workout.date) {
                scheduled += 1
                if overlapsBusy(workout: workout, availability: availability) {
                    conflicts += 1
                }
            } else {
                unscheduled += 1
            }
            if let request = requestFactory(workout) {
                validSlots += candidates(for: request, limit: 10).count
            }
        }
        let status: WeekScheduleFit.Status = conflicts > 0 ? .scheduleConflict : (unscheduled > 0 ? .needsScheduling : .fitsWell)
        return WeekScheduleFit(
            scheduledWorkouts: scheduled,
            unscheduledWorkouts: unscheduled,
            conflictingWorkouts: conflicts,
            availableValidSlots: validSlots,
            status: status
        )
    }

    func requiredWorkoutDurationSeconds(for workout: PlannedWorkout) -> TimeInterval {
        if let structureDuration = WorkoutStructure.estimatedDurationSeconds(workout.structure, fallbackPace: workout.paceBand) {
            return max(structureDuration, 20 * 60)
        }
        if let expected = workout.expectedDurationSeconds {
            return max(expected, 20 * 60)
        }
        switch workout.kind {
        case .long:
            return 120 * 60
        case .tempo, .intervals:
            return 60 * 60
        case .easy:
            return 45 * 60
        default:
            return 50 * 60
        }
    }

    private func bufferedStart(in window: AvailabilityWindow, preferences: SmartSchedulingPreferences, durationSeconds: TimeInterval) -> Date? {
        let earliestLimit = time(on: window.start, minutesFromMidnight: preferences.earliestStartMinutes)
        let latestFinish = time(on: window.start, minutesFromMidnight: preferences.latestFinishMinutes)
        let earliest = maxDate(window.start.addingTimeInterval(Double(preferences.bufferBeforeMinutes * 60)), earliestLimit)
        let latestWorkoutEnd = minDate(window.end.addingTimeInterval(Double(-preferences.bufferAfterMinutes * 60)), latestFinish)
        guard earliest.addingTimeInterval(durationSeconds) <= latestWorkoutEnd else { return nil }
        if let preferred = preferredWindow(on: window.start, preferences: preferences) {
            let preferredStart = maxDate(earliest, preferred.start)
            if preferredStart.addingTimeInterval(durationSeconds) <= minDate(latestWorkoutEnd, preferred.end) {
                return preferredStart
            }
        }
        return earliest
    }

    private func candidate(
        workout: PlannedWorkout,
        day: Date,
        start: Date,
        end: Date,
        availabilityWindow: AvailabilityWindow,
        preferences: SmartSchedulingPreferences,
        validation: ScheduleMoveValidation
    ) -> SchedulingCandidate {
        var score = 100
        var reasons = ["Available \(availabilityWindow.durationMinutes)-minute window"]
        var conflicts: [String] = []
        if validation.result == .safeAutomatic {
            reasons.append("Keeps the workout inside its training week")
        }
        if validation.result == .sameDayTimeOnly {
            reasons.append("Keeps the planned workout date")
        }
        if matchesPreferredTime(start, preferences: preferences) {
            score += 12
            reasons.append("Matches your preferred \(preferences.preferredTime.title.lowercased()) schedule")
        } else if preferences.preferredTime != .none {
            score -= 10
            reasons.append("Outside your preferred time")
        }
        let spare = availabilityWindow.durationMinutes - Int(end.timeIntervalSince(start) / 60)
        if spare >= preferences.bufferBeforeMinutes + preferences.bufferAfterMinutes + 20 {
            score += 8
            reasons.append("Leaves extra buffer around the workout")
        } else if spare < preferences.bufferBeforeMinutes + preferences.bufferAfterMinutes {
            conflicts.append("Required buffer does not fit")
        }
        if workout.kind?.isQuality == true {
            score += 6
            reasons.append("Respects hard-workout recovery spacing")
        }
        return SchedulingCandidate(
            workoutID: workout.uuid,
            date: day,
            startTime: start,
            endTime: end,
            score: max(0, min(150, score)),
            reasons: Array(reasons.prefix(4)),
            conflicts: conflicts
        )
    }

    private func overlapsBusy(workout: PlannedWorkout, availability: [DayAvailability]) -> Bool {
        guard isTimed(workout.date), let end = calendar.date(byAdding: .second, value: Int(requiredWorkoutDurationSeconds(for: workout)), to: workout.date) else {
            return false
        }
        guard let day = availability.first(where: { calendar.isDate($0.date, inSameDayAs: workout.date) }) else { return false }
        return day.busyWindows.contains { workout.date < $0.end && end > $0.start }
    }

    private func isTimed(_ date: Date) -> Bool {
        !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
    }

    private func preferredWindow(on date: Date, preferences: SmartSchedulingPreferences) -> (start: Date, end: Date)? {
        let range: (Int, Int)?
        switch preferences.preferredTime {
        case .none:
            range = nil
        case .earlyMorning:
            range = (5 * 60, 8 * 60)
        case .morning:
            range = (8 * 60, 11 * 60)
        case .lunch:
            range = (11 * 60, 14 * 60)
        case .afternoon:
            range = (14 * 60, 17 * 60)
        case .evening:
            range = (17 * 60, 21 * 60)
        case .custom:
            range = (preferences.earliestStartMinutes, preferences.latestFinishMinutes)
        }
        guard let range else { return nil }
        return (time(on: date, minutesFromMidnight: range.0), time(on: date, minutesFromMidnight: range.1))
    }

    private func matchesPreferredTime(_ date: Date, preferences: SmartSchedulingPreferences) -> Bool {
        guard let window = preferredWindow(on: date, preferences: preferences) else { return true }
        return date >= window.start && date < window.end
    }

    private func time(on date: Date, minutesFromMidnight: Int) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutesFromMidnight, to: day) ?? day
    }

    private func maxDate(_ lhs: Date, _ rhs: Date) -> Date { lhs > rhs ? lhs : rhs }
    private func minDate(_ lhs: Date, _ rhs: Date) -> Date { lhs < rhs ? lhs : rhs }
}

extension WorkoutStructure {
    static func estimatedDurationSeconds(_ groups: [WorkoutStepGroup], fallbackPace: PaceBand?) -> Double? {
        guard !groups.isEmpty else { return nil }
        let pace = fallbackPace.map { ($0.fastSecondsPerKm + $0.slowSecondsPerKm) / 2 } ?? 390
        let total = groups.reduce(0.0) { partial, group in
            partial + group.steps.reduce(0.0) { stepTotal, step in
                if let seconds = step.durationSeconds {
                    return stepTotal + seconds
                }
                if let km = step.distanceKm {
                    let stepPace = step.paceBand.map { ($0.fastSecondsPerKm + $0.slowSecondsPerKm) / 2 } ?? pace
                    return stepTotal + km * stepPace
                }
                return stepTotal
            } * Double(max(group.repeatCount, 1))
        }
        return total > 0 ? total : nil
    }
}
