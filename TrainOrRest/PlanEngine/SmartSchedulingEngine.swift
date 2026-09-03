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
    var allowsLockedWorkoutUpdate = false
}

enum SchedulingValidationStatus: String, Codable, CaseIterable, Equatable {
    case valid
    case validWithWarning
    case calendarConflict
    case trainingConflict
    case outsideUserPreference
    case invalid
    case stale

    var allowsScheduling: Bool {
        self == .valid || self == .validWithWarning || self == .outsideUserPreference
    }
}

struct SchedulingCandidate: Identifiable, Equatable {
    var id: String { "\(workoutID.uuidString)-\(Int(startTime.timeIntervalSince1970))-\(timezone.identifier)" }
    var workoutID: UUID
    var workoutVersion: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var timezone: TimeZone
    var score: Int
    var isRecommended: Bool
    var validationStatus: SchedulingValidationStatus
    var reasons: [String]
    var warnings: [String]
    var conflicts: [String]
    var availabilitySourceTimestamp: Date?

    var isValid: Bool { validationStatus.allowsScheduling && conflicts.isEmpty }
}

struct CustomTimeValidation: Equatable {
    var status: SchedulingValidationStatus
    var requestedStart: Date
    var calculatedEnd: Date
    var conflicts: [String]
    var warnings: [String]
    var reasons: [String]
    var nearestAlternatives: [SchedulingCandidate]
    var availabilitySourceTimestamp: Date?

    var allowsScheduling: Bool { status.allowsScheduling && conflicts.isEmpty }
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
        guard !request.workout.isScheduleLocked || request.allowsLockedWorkoutUpdate else { return [] }
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
                for start in candidateStarts(in: window, preferences: request.userPreferences, durationSeconds: duration) {
                    guard let end = calendar.date(byAdding: .second, value: Int(duration), to: start) else { continue }
                    let candidate = candidate(
                    workout: request.workout,
                    day: day,
                    start: start,
                    end: end,
                    availabilityWindow: window,
                    availabilitySourceTimestamp: availability.lastRefreshedAt,
                    preferences: request.userPreferences,
                    validation: validationResult,
                    request: request
                    )
                    if candidate.isValid {
                        output.append(candidate)
                    }
                }
            }
        }
        var sorted = output
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.startTime < rhs.startTime
            }
            .prefix(limit)
            .map { $0 }
        if !sorted.isEmpty {
            sorted[0].isRecommended = true
        }
        return sorted
    }

    func validateCustomTime(start: Date, for request: SchedulingRequest, now: Date = .now, alternativesLimit: Int = 2) -> CustomTimeValidation {
        let duration = requiredWorkoutDurationSeconds(for: request.workout)
        let end = calendar.date(byAdding: .second, value: Int(duration), to: start) ?? start
        let alternatives = candidates(for: request, limit: max(alternativesLimit, 1))
        guard !request.workout.isScheduleLocked || request.allowsLockedWorkoutUpdate else {
            return customValidation(
                status: .invalid,
                start: start,
                end: end,
                conflicts: ["This workout is fixed."],
                warnings: [],
                reasons: [],
                alternatives: alternatives,
                availabilitySourceTimestamp: nil
            )
        }
        guard start > now else {
            return customValidation(
                status: .invalid,
                start: start,
                end: end,
                conflicts: ["This time has already passed."],
                warnings: [],
                reasons: [],
                alternatives: alternatives,
                availabilitySourceTimestamp: nil
            )
        }
        guard let availability = request.availability.first(where: { calendar.isDate($0.date, inSameDayAs: start) }) else {
            return customValidation(
                status: .stale,
                start: start,
                end: end,
                conflicts: ["Calendar availability needs to be refreshed."],
                warnings: [],
                reasons: [],
                alternatives: alternatives,
                availabilitySourceTimestamp: nil
            )
        }
        let validationResult = validation.validate(
            workout: request.workout,
            targetDate: start,
            allWorkouts: request.surroundingWorkouts,
            plan: request.plan,
            goal: request.goal
        )
        guard validationResult.result == .safeAutomatic || validationResult.result == .sameDayTimeOnly else {
            return customValidation(
                status: .trainingConflict,
                start: start,
                end: end,
                conflicts: validationResult.reasons.isEmpty ? ["This time is not safe for the current plan."] : validationResult.reasons,
                warnings: [],
                reasons: [],
                alternatives: alternatives,
                availabilitySourceTimestamp: availability.lastRefreshedAt
            )
        }

        let bufferStart = start.addingTimeInterval(Double(-request.userPreferences.bufferBeforeMinutes * 60))
        let bufferEnd = end.addingTimeInterval(Double(request.userPreferences.bufferAfterMinutes * 60))
        let conflictingBusy = availability.busyWindows.first { bufferStart < $0.end && bufferEnd > $0.start }
        if let conflict = conflictingBusy {
            return customValidation(
                status: .calendarConflict,
                start: start,
                end: end,
                conflicts: ["Your calendar is busy from \(timeText(conflict.start)) to \(timeText(conflict.end))."],
                warnings: [],
                reasons: [],
                alternatives: nearestAlternatives(to: start, from: alternatives, limit: alternativesLimit),
                availabilitySourceTimestamp: availability.lastRefreshedAt
            )
        }

        let startMinute = minuteOfDay(start)
        let endMinute = minuteOfDay(end)
        if startMinute < request.userPreferences.earliestStartMinutes {
            return customValidation(
                status: .invalid,
                start: start,
                end: end,
                conflicts: ["This starts before your earliest allowed start."],
                warnings: [],
                reasons: [],
                alternatives: nearestAlternatives(to: start, from: alternatives, limit: alternativesLimit),
                availabilitySourceTimestamp: availability.lastRefreshedAt
            )
        }
        if endMinute > request.userPreferences.latestFinishMinutes {
            return customValidation(
                status: .invalid,
                start: start,
                end: end,
                conflicts: ["This finishes after your latest allowed finish."],
                warnings: [],
                reasons: [],
                alternatives: nearestAlternatives(to: start, from: alternatives, limit: alternativesLimit),
                availabilitySourceTimestamp: availability.lastRefreshedAt
            )
        }

        var warnings: [String] = []
        var status: SchedulingValidationStatus = .valid
        if !matchesPreferredTime(start, preferences: request.userPreferences), request.userPreferences.preferredTime != .none {
            status = .outsideUserPreference
            warnings.append("This is outside your preferred \(request.userPreferences.preferredTime.title.lowercased()) window.")
        }
        return customValidation(
            status: status,
            start: start,
            end: end,
            conflicts: [],
            warnings: warnings,
            reasons: [
                "No calendar conflicts",
                "Required duration fits",
                "Recovery spacing is safe"
            ],
            alternatives: nearestAlternatives(to: start, from: alternatives, limit: alternativesLimit),
            availabilitySourceTimestamp: availability.lastRefreshedAt
        )
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

    private func candidateStarts(in window: AvailabilityWindow, preferences: SmartSchedulingPreferences, durationSeconds: TimeInterval) -> [Date] {
        let earliestLimit = time(on: window.start, minutesFromMidnight: preferences.earliestStartMinutes)
        let latestFinish = time(on: window.start, minutesFromMidnight: preferences.latestFinishMinutes)
        let earliest = maxDate(window.start.addingTimeInterval(Double(preferences.bufferBeforeMinutes * 60)), earliestLimit)
        let latestWorkoutEnd = minDate(window.end.addingTimeInterval(Double(-preferences.bufferAfterMinutes * 60)), latestFinish)
        guard earliest.addingTimeInterval(durationSeconds) <= latestWorkoutEnd else { return [] }
        let latestStart = latestWorkoutEnd.addingTimeInterval(-durationSeconds)
        var starts: Set<Date> = [alignToQuarterHour(earliest)]
        if let preferred = preferredWindow(on: window.start, preferences: preferences) {
            let preferredStart = maxDate(earliest, preferred.start)
            if preferredStart.addingTimeInterval(durationSeconds) <= minDate(latestWorkoutEnd, preferred.end) {
                starts.insert(alignToQuarterHour(preferredStart))
            }
        }
        var cursor = alignToQuarterHour(earliest)
        while cursor <= latestStart {
            starts.insert(cursor)
            guard let next = calendar.date(byAdding: .minute, value: 30, to: cursor), next > cursor else { break }
            cursor = next
        }
        return starts
            .filter { $0 >= earliest && $0 <= latestStart }
            .sorted()
    }

    private func candidate(
        workout: PlannedWorkout,
        day: Date,
        start: Date,
        end: Date,
        availabilityWindow: AvailabilityWindow,
        availabilitySourceTimestamp: Date?,
        preferences: SmartSchedulingPreferences,
        validation: ScheduleMoveValidation,
        request: SchedulingRequest
    ) -> SchedulingCandidate {
        var score = 100
        var reasons = ["No calendar conflicts"]
        var warnings: [String] = []
        var conflicts: [String] = []
        if validation.result == .safeAutomatic {
            reasons.append("Keeps the workout inside its training week")
        }
        if validation.result == .sameDayTimeOnly {
            score += 18
            reasons.append("Keeps the planned workout date")
        }
        if matchesPreferredTime(start, preferences: preferences) {
            score += 12
            reasons.append("Matches your preferred \(preferences.preferredTime.title.lowercased()) schedule")
        } else if preferences.preferredTime != .none {
            score -= 10
            warnings.append("Outside your preferred \(preferences.preferredTime.title.lowercased()) window.")
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
            workoutVersion: workoutVersion(for: workout),
            date: day,
            startTime: start,
            endTime: end,
            timezone: request.timezone,
            score: max(0, min(150, score)),
            isRecommended: false,
            validationStatus: warnings.isEmpty ? .valid : .outsideUserPreference,
            reasons: Array(reasons.prefix(4)),
            warnings: warnings,
            conflicts: conflicts,
            availabilitySourceTimestamp: availabilitySourceTimestamp
        )
    }

    private func customValidation(
        status: SchedulingValidationStatus,
        start: Date,
        end: Date,
        conflicts: [String],
        warnings: [String],
        reasons: [String],
        alternatives: [SchedulingCandidate],
        availabilitySourceTimestamp: Date?
    ) -> CustomTimeValidation {
        CustomTimeValidation(
            status: status,
            requestedStart: start,
            calculatedEnd: end,
            conflicts: conflicts,
            warnings: warnings,
            reasons: reasons,
            nearestAlternatives: alternatives,
            availabilitySourceTimestamp: availabilitySourceTimestamp
        )
    }

    private func nearestAlternatives(to date: Date, from candidates: [SchedulingCandidate], limit: Int) -> [SchedulingCandidate] {
        Array(candidates.sorted {
            abs($0.startTime.timeIntervalSince(date)) < abs($1.startTime.timeIntervalSince(date))
        }.prefix(limit))
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

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func alignToQuarterHour(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = components.minute ?? 0
        let rounded = Int(ceil(Double(minute) / 15.0)) * 15
        var aligned = components
        aligned.minute = rounded % 60
        aligned.hour = (components.hour ?? 0) + rounded / 60
        return calendar.date(from: aligned) ?? date
    }

    private func workoutVersion(for workout: PlannedWorkout) -> String {
        [
            workout.uuid.uuidString,
            workout.date.ISO8601Format(),
            workout.kindRaw,
            String(format: "%.3f", workout.distanceKm),
            workout.statusRaw,
            workout.scheduleUpdatedAt?.ISO8601Format() ?? "none",
            workout.isScheduleLocked ? "locked" : "unlocked"
        ].joined(separator: "|")
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
