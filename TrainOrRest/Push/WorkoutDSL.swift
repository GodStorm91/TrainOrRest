import Foundation

enum WorkoutDSL {
    static func event(for workout: PlannedWorkout, calendar: Calendar) -> IntervalsWorkoutEvent? {
        guard let kind = workout.kind, kind != .race else { return nil }
        let structure = workout.structure.isEmpty
            ? WorkoutStructure.run(distanceKm: workout.distanceKm, paceBand: workout.paceBand)
            : workout.structure

        return IntervalsWorkoutEvent(
            externalID: externalID(for: workout.uuid),
            startDateLocal: startDateLocal(for: workout.date, calendar: calendar),
            name: eventName(kind: kind, structure: structure),
            description: render(kind: kind, structure: structure),
            movingTime: movingTimeSeconds(structure)
        )
    }

    static func externalID(for uuid: UUID) -> String {
        "trainorrest-\(uuid.uuidString.lowercased())"
    }

    static func render(kind: WorkoutKind, structure: [WorkoutStepGroup]) -> String {
        structure.enumerated()
            .map { block(kind: kind, group: $0.element, index: $0.offset) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func eventName(kind: WorkoutKind, structure: [WorkoutStepGroup]) -> String {
        switch kind {
        case .easy:
            "Easy Run - \(formatDistance(WorkoutStructure.totalDistanceKm(structure)))"
        case .long:
            "Long Run - \(formatDistance(WorkoutStructure.totalDistanceKm(structure)))"
        case .tempo:
            "Tempo - \(formatDistance(workDistance(in: structure))) @ T pace"
        case .threshold:
            "Threshold - \(formatDistance(workDistance(in: structure))) @ T pace"
        case .intervals:
            intervalEventName(structure)
        case .race:
            "Race"
        }
    }

    static func movingTimeSeconds(_ structure: [WorkoutStepGroup]) -> Int {
        Int(WorkoutStructure.estimatedDurationSeconds(structure).rounded())
    }

    private static func block(kind: WorkoutKind, group: WorkoutStepGroup, index: Int) -> String {
        let lines = group.steps.map(stepLine)
        guard !lines.isEmpty else { return "" }
        if let title = groupTitle(kind: kind, group: group, index: index) {
            return ([title] + lines).joined(separator: "\n")
        }
        return lines.joined(separator: "\n")
    }

    private static func groupTitle(kind: WorkoutKind, group: WorkoutStepGroup, index: Int) -> String? {
        if group.repeatCount > 1 {
            return "Main set \(group.repeatCount)x"
        }

        guard group.steps.count == 1, let role = group.steps.first?.role else {
            return index == 0 ? "Main set" : nil
        }

        switch role {
        case .warmUp:
            return "Warmup"
        case .coolDown:
            return "Cooldown"
        case .recovery:
            return "Recovery"
        case .work:
            switch kind {
            case .tempo:
                return "Tempo"
            case .threshold:
                return "Threshold"
            case .intervals:
                return "Main set"
            case .easy, .long, .race:
                return nil
            }
        }
    }

    private static func stepLine(_ step: WorkoutStep) -> String {
        let target = step.distanceKm.map { formatDistance($0) }
            ?? step.durationSeconds.map { formatDuration($0) }
            ?? "0s"
        // Always send a pace target: an easy/long run built without current
        // fitness has no band, and a distance-only line reaches the watch with
        // no pace. Fall back to a conservative easy pace so the target is set.
        let paceBand = step.paceBand ?? WorkoutStructure.fallbackEasyBand
        return "- \(target) \(formatPaceBand(paceBand))"
    }

    private static func intervalEventName(_ structure: [WorkoutStepGroup]) -> String {
        guard let group = structure.first(where: { $0.repeatCount > 1 }),
              let work = group.steps.first(where: { $0.role == .work }),
              let distance = work.distanceKm else {
            return "Intervals - \(formatDistance(workDistance(in: structure)))"
        }
        return "Intervals - \(group.repeatCount) x \(formatDistance(distance)) @ I pace"
    }

    private static func workDistance(in structure: [WorkoutStepGroup]) -> Double {
        structure.reduce(0) { total, group in
            total + Double(group.repeatCount) * group.steps.reduce(0) { stepTotal, step in
                step.role == .work ? stepTotal + (step.distanceKm ?? 0) : stepTotal
            }
        }
    }

    private static func startDateLocal(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02dT00:00:00",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    private static func formatDistance(_ km: Double) -> String {
        "\(trimmedDecimal(km))km"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m\(remainder)"
    }

    private static func formatPaceBand(_ band: PaceBand) -> String {
        let fast = min(band.fastSecondsPerKm, band.slowSecondsPerKm)
        let slow = max(band.fastSecondsPerKm, band.slowSecondsPerKm)
        return "\(formatPace(slow))-\(formatPace(fast))/km Pace"
    }

    private static func formatPace(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private static func trimmedDecimal(_ value: Double) -> String {
        let raw = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        return raw
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
