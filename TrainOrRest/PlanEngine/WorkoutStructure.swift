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

    static func run(distanceKm: Double, paceBand: PaceBand?) -> [WorkoutStepGroup] {
        [
            WorkoutStepGroup(steps: [
                WorkoutStep(role: .work, distanceKm: distanceKm, paceBand: paceBand)
            ])
        ]
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
    static func details(for kind: WorkoutKind, structure: [WorkoutStepGroup]) -> String {
        switch kind {
        case .easy:
            return "Easy run at E pace"
        case .long:
            return "Long run at E pace"
        case .tempo:
            let workKm = structure.flatMap(\.steps).first { $0.role == .work }?.distanceKm ?? 0
            return "2 km warm-up · \(formatKm(workKm)) km at T pace · 2 km cool-down"
        case .intervals:
            let repeatCount = structure.first(where: { $0.repeatCount > 1 })?.repeatCount ?? 0
            return "2 km warm-up · \(repeatCount) × 1 km at I pace (2–3 min jog) · 2 km cool-down"
        case .race:
            return ""
        }
    }

    private static func formatKm(_ km: Double) -> String {
        km.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(km)) : String(format: "%.1f", km)
    }
}
