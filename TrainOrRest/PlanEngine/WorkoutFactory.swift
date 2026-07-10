import Foundation

/// The pace zone a step is run at. The app owns the mapping from zone to a real
/// pace band derived from current fitness; a model never supplies pace seconds.
enum PaceZone: String, Codable, Equatable, CaseIterable {
    case easy, threshold, interval, none

    /// Quality zones require current fitness; easy/none degrade to an unpaced step.
    var isQuality: Bool { self == .threshold || self == .interval }

    func band(from paces: TrainingPaces?) -> PaceBand? {
        switch self {
        case .none: nil
        case .easy: paces?.easy
        case .threshold: paces?.threshold
        case .interval: paces?.interval
        }
    }
}

/// A workout described in zones and targets, before the app resolves paces.
/// Both the generator's canonical templates and coach-proposed payloads become
/// a recipe first, so there is exactly one construction path.
struct WorkoutRecipe: Equatable {
    struct Step: Equatable {
        var role: WorkoutStepRole
        var distanceKm: Double?
        var durationSeconds: Double?
        var zone: PaceZone

        static func distance(_ role: WorkoutStepRole, _ km: Double, _ zone: PaceZone) -> Step {
            Step(role: role, distanceKm: km, durationSeconds: nil, zone: zone)
        }

        static func duration(_ role: WorkoutStepRole, _ seconds: Double, _ zone: PaceZone) -> Step {
            Step(role: role, distanceKm: nil, durationSeconds: seconds, zone: zone)
        }
    }

    struct Block: Equatable {
        var repeatCount: Int
        var steps: [Step]
    }

    var kind: WorkoutKind
    var blocks: [Block]
}

/// The app-owned result of building a recipe: stored structure plus every value
/// derived from it. Distance counts distance-targeted steps only — duration
/// steps (interval recoveries) add time, which is how the generator has always
/// measured a session.
struct BuiltWorkout: Equatable {
    var kind: WorkoutKind
    var structure: [WorkoutStepGroup]
    var distanceKm: Double
    var paceBand: PaceBand?
    var details: String
}

struct WorkoutBuildError: LocalizedError, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Canonical workout construction shared by `PlanGenerator` and `CoachTools`.
enum WorkoutFactory {
    enum Limits {
        static let maxBlocks = 12
        static let maxStepsPerBlock = 12
        static let maxRepeatCount = 30
        static let maxStepDistanceKm = 60.0
        static let maxStepDurationSeconds = 7_200.0
        static let maxTotalDistanceKm = 80.0
    }

    /// Canonical quality-session shape: 2 km easy either side of the work.
    static let warmupKm = 2.0
    static let cooldownKm = 2.0
    /// Canonical interval recovery jog.
    static let intervalRecoverySeconds = 150.0
    static let intervalRepDistanceKm = 1.0

    // MARK: - Canonical recipes

    static func canonicalEasy(distanceKm: Double, paces: TrainingPaces?) -> BuiltWorkout {
        assemble(singleRun(kind: .easy, distanceKm: distanceKm), paces: paces)
    }

    static func canonicalLong(distanceKm: Double, paces: TrainingPaces?) -> BuiltWorkout {
        assemble(singleRun(kind: .long, distanceKm: distanceKm), paces: paces)
    }

    static func canonicalTempo(tempoKm: Double, paces: TrainingPaces) -> BuiltWorkout {
        assemble(tempoRecipe(tempoKm: tempoKm), paces: paces)
    }

    static func canonicalIntervals(repCount: Int, paces: TrainingPaces) -> BuiltWorkout {
        assemble(intervalRecipe(repCount: repCount), paces: paces)
    }

    static func singleRun(kind: WorkoutKind, distanceKm: Double) -> WorkoutRecipe {
        WorkoutRecipe(kind: kind, blocks: [
            .init(repeatCount: 1, steps: [.distance(.work, distanceKm, .easy)])
        ])
    }

    static func tempoRecipe(tempoKm: Double) -> WorkoutRecipe {
        WorkoutRecipe(kind: .tempo, blocks: [
            .init(repeatCount: 1, steps: [.distance(.warmUp, warmupKm, .easy)]),
            .init(repeatCount: 1, steps: [.distance(.work, tempoKm, .threshold)]),
            .init(repeatCount: 1, steps: [.distance(.coolDown, cooldownKm, .easy)])
        ])
    }

    static func intervalRecipe(repCount: Int) -> WorkoutRecipe {
        WorkoutRecipe(kind: .intervals, blocks: [
            .init(repeatCount: 1, steps: [.distance(.warmUp, warmupKm, .easy)]),
            .init(repeatCount: repCount, steps: [
                .distance(.work, intervalRepDistanceKm, .interval),
                .duration(.recovery, intervalRecoverySeconds, .easy)
            ]),
            .init(repeatCount: 1, steps: [.distance(.coolDown, cooldownKm, .easy)])
        ])
    }

    // MARK: - Untrusted recipes

    /// Validates a recipe (model-authored or otherwise) and builds it. Throws a
    /// user-readable error rather than constructing an unsafe workout.
    static func build(_ recipe: WorkoutRecipe, paces: TrainingPaces?) throws -> BuiltWorkout {
        try validate(recipe, paces: paces)
        return assemble(recipe, paces: paces)
    }

    private static func validate(_ recipe: WorkoutRecipe, paces: TrainingPaces?) throws {
        guard recipe.kind != .race else {
            throw WorkoutBuildError("Race workouts cannot be created.")
        }
        guard !recipe.blocks.isEmpty, recipe.blocks.count <= Limits.maxBlocks else {
            throw WorkoutBuildError("A workout needs 1 to \(Limits.maxBlocks) blocks.")
        }

        for block in recipe.blocks {
            guard (1...Limits.maxRepeatCount).contains(block.repeatCount) else {
                throw WorkoutBuildError("repeat_count must be 1 to \(Limits.maxRepeatCount).")
            }
            guard !block.steps.isEmpty, block.steps.count <= Limits.maxStepsPerBlock else {
                throw WorkoutBuildError("A block needs 1 to \(Limits.maxStepsPerBlock) steps.")
            }
            for step in block.steps {
                try validate(step)
                if step.zone.isQuality, paces == nil {
                    throw WorkoutBuildError("Not enough recent running data to set \(step.zone.rawValue) pace.")
                }
            }
        }

        try validateShape(recipe)

        let total = totalDistanceKm(recipe)
        guard total.isFinite, total > 0, total <= Limits.maxTotalDistanceKm else {
            throw WorkoutBuildError("Total distance must be above 0 and at most \(Int(Limits.maxTotalDistanceKm)) km.")
        }
    }

    private static func validate(_ step: WorkoutRecipe.Step) throws {
        switch (step.distanceKm, step.durationSeconds) {
        case let (km?, nil):
            guard km.isFinite, km > 0, km <= Limits.maxStepDistanceKm else {
                throw WorkoutBuildError("Step distance must be above 0 and at most \(Int(Limits.maxStepDistanceKm)) km.")
            }
        case let (nil, seconds?):
            guard seconds.isFinite, seconds > 0, seconds <= Limits.maxStepDurationSeconds else {
                throw WorkoutBuildError("Step duration must be above 0 and at most \(Int(Limits.maxStepDurationSeconds)) seconds.")
            }
        default:
            throw WorkoutBuildError("Each step needs exactly one of distance_km or duration_seconds.")
        }
    }

    /// Kind-specific role/zone rules. These keep coach-created sessions on the
    /// same shapes the generator produces.
    private static func validateShape(_ recipe: WorkoutRecipe) throws {
        let steps = recipe.blocks.flatMap(\.steps)
        switch recipe.kind {
        case .easy, .long:
            guard recipe.blocks.count == 1,
                  let block = recipe.blocks.first,
                  block.repeatCount == 1,
                  block.steps.count == 1,
                  let step = block.steps.first,
                  step.role == .work,
                  step.distanceKm != nil,
                  !step.zone.isQuality
            else {
                throw WorkoutBuildError("\(recipe.kind.rawValue) runs must be one easy-paced distance step.")
            }
        case .tempo:
            guard steps.contains(where: { $0.role == .work }) else {
                throw WorkoutBuildError("A tempo needs a work step.")
            }
            for step in steps {
                switch step.role {
                case .work:
                    guard step.zone == .threshold else {
                        throw WorkoutBuildError("Tempo work must use threshold pace.")
                    }
                case .warmUp, .coolDown:
                    guard !step.zone.isQuality else {
                        throw WorkoutBuildError("Warm-up and cool-down must be easy.")
                    }
                case .recovery:
                    throw WorkoutBuildError("Tempo workouts have no recovery steps.")
                }
            }
        case .intervals:
            guard recipe.blocks.contains(where: { $0.steps.contains { $0.role == .work } }) else {
                throw WorkoutBuildError("An interval session needs a work step.")
            }
            for step in steps {
                switch step.role {
                case .work:
                    guard step.zone == .interval else {
                        throw WorkoutBuildError("Interval work must use interval pace.")
                    }
                case .recovery, .warmUp, .coolDown:
                    guard !step.zone.isQuality else {
                        throw WorkoutBuildError("Recovery, warm-up and cool-down must be easy.")
                    }
                }
            }
        case .race:
            throw WorkoutBuildError("Race workouts cannot be created.")
        }
    }

    // MARK: - Assembly

    private static func assemble(_ recipe: WorkoutRecipe, paces: TrainingPaces?) -> BuiltWorkout {
        let groups = recipe.blocks.map { block in
            WorkoutStepGroup(repeatCount: block.repeatCount, steps: block.steps.map { step in
                let band = step.zone.band(from: paces)
                if let km = step.distanceKm {
                    return WorkoutStep(role: step.role, distanceKm: km, paceBand: band)
                }
                return WorkoutStep(role: step.role, durationSeconds: step.durationSeconds ?? 0, paceBand: band)
            })
        }
        let workZone = recipe.blocks.flatMap(\.steps).first { $0.role == .work }?.zone ?? .none
        return BuiltWorkout(
            kind: recipe.kind,
            structure: groups,
            distanceKm: roundedKm(WorkoutStructure.totalDistanceKm(groups)),
            paceBand: workZone.band(from: paces),
            details: WorkoutProse.details(for: recipe.kind, structure: groups)
        )
    }

    static func totalDistanceKm(_ recipe: WorkoutRecipe) -> Double {
        recipe.blocks.reduce(0) { total, block in
            total + Double(block.repeatCount) * block.steps.reduce(0) { $0 + ($1.distanceKm ?? 0) }
        }
    }

    /// Round to 0.1 km so plans display cleanly and compare exactly.
    static func roundedKm(_ km: Double) -> Double { (km * 10).rounded() / 10 }
}
