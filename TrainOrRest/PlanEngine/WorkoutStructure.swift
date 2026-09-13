import Foundation

enum WorkoutStepRole: String, Codable, Equatable {
    case warmUp, work, recovery, coolDown
}

struct WorkoutStep: Codable, Equatable {
    var role: WorkoutStepRole
    var distanceKm: Double?
    var durationSeconds: Double?
    var paceBand: PaceBand?

    init(role: WorkoutStepRole, distanceKm: Double, paceBand: PaceBand? = nil) {
        self.role = role
        self.distanceKm = distanceKm
        self.durationSeconds = nil
        self.paceBand = paceBand
    }

    init(role: WorkoutStepRole, durationSeconds: Double, paceBand: PaceBand? = nil) {
        self.role = role
        self.distanceKm = nil
        self.durationSeconds = durationSeconds
        self.paceBand = paceBand
    }
}

struct WorkoutStepGroup: Codable, Equatable {
    var repeatCount: Int
    var steps: [WorkoutStep]

    init(repeatCount: Int = 1, steps: [WorkoutStep]) {
        self.repeatCount = max(1, repeatCount)
        self.steps = steps
    }
}

enum WorkoutStructure {
    static let fallbackEasyPaceSecondsPerKm: Double = 360

    /// Default easy pace band used when a run step has no fitness-derived pace
    /// (e.g. an easy/long run built while current fitness was unavailable).
    /// Keeps pushed workouts from reaching the watch with distance but no pace.
    static let fallbackEasyBand = PaceBand(
        fastSecondsPerKm: fallbackEasyPaceSecondsPerKm,
        slowSecondsPerKm: fallbackEasyPaceSecondsPerKm + 30
    )

    static func run(distanceKm: Double, paceBand: PaceBand?) -> [WorkoutStepGroup] {
        [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .work, distanceKm: distanceKm, paceBand: paceBand)
            ])
        ]
    }

    /// True when every work step carries a pace band. Quality work built
    /// without current fitness has none, and its labels must say so.
    static func workHasPaceBand(_ structure: [WorkoutStepGroup]) -> Bool {
        let work = structure.flatMap(\.steps).filter { $0.role == .work }
        return !work.isEmpty && work.allSatisfy { $0.paceBand != nil }
    }

    static func easyRun(distanceKm: Double, paces: TrainingPaces) -> [WorkoutStepGroup] {
        run(distanceKm: distanceKm, paceBand: paces.easy)
    }

    static func totalDistanceKm(_ groups: [WorkoutStepGroup]) -> Double {
        groups.reduce(0) { total, group in
            total + Double(group.repeatCount) * group.steps.reduce(0) { stepTotal, step in
                stepTotal + (step.distanceKm ?? 0)
            }
        }
    }

    static func estimatedDurationSeconds(_ groups: [WorkoutStepGroup]) -> Double {
        groups.reduce(0) { total, group in
            total + Double(group.repeatCount) * group.steps.reduce(0) { stepTotal, step in
                stepTotal + durationSeconds(for: step)
            }
        }
    }

    private static func durationSeconds(for step: WorkoutStep) -> Double {
        if let duration = step.durationSeconds {
            return duration
        }
        guard let distance = step.distanceKm else { return 0 }
        let pace = step.paceBand.map {
            ($0.fastSecondsPerKm + $0.slowSecondsPerKm) / 2
        } ?? fallbackEasyPaceSecondsPerKm
        return distance * pace
    }
}

enum WorkoutProse {
    /// Prose rendered from the structure itself, so a coach-created session
    /// describes its own warm-up, work and recovery rather than the canonical
    /// template's. Canonical structures render exactly as they always have.
    static func details(for kind: WorkoutKind, structure: [WorkoutStepGroup]) -> String {
        switch kind {
        case .easy:
            return "Easy run at E pace"
        case .long:
            return "Long run at E pace"
        case .tempo, .threshold:
            let steps = structure.flatMap(\.steps)
            var parts: [String] = []
            if let warmUp = steps.first(where: { $0.role == .warmUp })?.distanceKm {
                parts.append("\(formatKm(warmUp)) km warm-up")
            }
            let work = steps.first { $0.role == .work }
            let workKm = work?.distanceKm ?? 0
            parts.append("\(formatKm(workKm)) km \(work?.paceBand == nil ? "by effort" : "at T pace")")
            if let coolDown = steps.first(where: { $0.role == .coolDown })?.distanceKm {
                parts.append("\(formatKm(coolDown)) km cool-down")
            }
            return parts.joined(separator: " · ")
        case .intervals:
            let steps = structure.flatMap(\.steps)
            var parts: [String] = []
            if let warmUp = steps.first(where: { $0.role == .warmUp })?.distanceKm {
                parts.append("\(formatKm(warmUp)) km warm-up")
            }
            let workGroup = structure.first { $0.steps.contains { $0.role == .work } }
            let reps = workGroup?.repeatCount ?? 0
            let work = workGroup?.steps.first { $0.role == .work }
            let repKm = work?.distanceKm ?? 0
            var core = "\(reps) × \(formatKm(repKm)) km \(work?.paceBand == nil ? "by effort" : "at I pace")"
            if let recovery = workGroup?.steps.first(where: { $0.role == .recovery })?.durationSeconds {
                core += " (\(recoveryPhrase(recovery)))"
            }
            parts.append(core)
            if let coolDown = steps.first(where: { $0.role == .coolDown })?.distanceKm {
                parts.append("\(formatKm(coolDown)) km cool-down")
            }
            return parts.joined(separator: " · ")
        case .race:
            return ""
        }
    }

    /// The canonical jog is described as a range because the exact stored value
    /// is a midpoint, not a prescription. Other recoveries print their real time.
    private static func recoveryPhrase(_ seconds: Double) -> String {
        guard seconds != WorkoutFactory.intervalRecoverySeconds else { return "2–3 min jog" }
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d jog", whole / 60, whole % 60)
    }

    private static func formatKm(_ km: Double) -> String {
        km.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(km)) : String(format: "%.1f", km)
    }
}
