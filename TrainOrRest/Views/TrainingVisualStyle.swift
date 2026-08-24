import SwiftUI

/// Semantic accents mapped onto the dark-cockpit Theme so every consumer
/// (activity/workout rows, plan phases, status chips) matches the redesign.
enum TrainingVisualStyle {
    static let easy = Theme.good
    static let long = Theme.accent
    static let tempo = Theme.warn
    static let threshold = Theme.warn
    static let intervals = Theme.accent2
    static let race = Theme.accent2
    static let recovery = Theme.good
    static let sleep = Theme.data
    static let heart = Theme.data
    static let oxygen = Theme.data

    static func tint(_ color: Color, opacity: Double = 0.14) -> Color {
        color.opacity(opacity)
    }
}

extension WorkoutKind {
    var styleColor: Color {
        switch self {
        case .easy: TrainingVisualStyle.easy
        case .long: TrainingVisualStyle.long
        case .tempo: TrainingVisualStyle.tempo
        case .threshold: TrainingVisualStyle.threshold
        case .intervals: TrainingVisualStyle.intervals
        case .race: TrainingVisualStyle.race
        }
    }
}

extension TrainingPhase {
    var styleColor: Color {
        switch self {
        case .base: TrainingVisualStyle.easy
        case .build: TrainingVisualStyle.tempo
        case .peak: TrainingVisualStyle.intervals
        case .taper: TrainingVisualStyle.recovery
        }
    }
}

extension WorkoutStatus {
    var chipText: String {
        switch self {
        case .planned: "Planned"
        case .done: "Done"
        case .skipped: "Skipped"
        }
    }

    var chipColor: Color {
        switch self {
        case .planned: .secondary
        case .done: TrainingVisualStyle.easy
        case .skipped: TrainingVisualStyle.tempo
        }
    }
}

/// Coarse effort classification of a completed run, derived from its real
/// heart-rate / pace / distance — not a stored or fabricated score.
enum RunEffort {
    case easy, tempo, long, intervals

    var color: Color {
        switch self {
        case .easy: TrainingVisualStyle.easy
        case .tempo: TrainingVisualStyle.tempo
        case .long: TrainingVisualStyle.long
        case .intervals: TrainingVisualStyle.intervals
        }
    }

    var label: String {
        switch self {
        case .easy: "Easy"
        case .tempo: "Tempo"
        case .long: "Long run"
        case .intervals: "Intervals"
        }
    }
}

extension CompletedActivity {
    var effort: RunEffort {
        if let avgHeartRate, avgHeartRate >= 165 { return .intervals }
        if let avgPaceSecondsPerKm, avgPaceSecondsPerKm < 300 { return .tempo }
        if let distanceMeters, distanceMeters >= 12_000 { return .long }
        return .easy
    }

    var effortColor: Color { effort.color }
    var effortLabel: String { effort.label }
}

extension ReadinessVerdict {
    /// Legacy verdict word retained for existing call sites outside the retired ring.
    var torWord: String {
        switch self {
        case .train: "TRAIN"
        case .goEasy: "EASY"
        case .rest: "REST"
        case .insufficientData: "BASELINE"
        }
    }

    /// Verdict role color per the non-alarm palette.
    var torColor: Color {
        switch self {
        case .train: Theme.verdictTrain
        case .goEasy: Theme.verdictEasy
        case .rest: Theme.verdictRest
        case .insufficientData: Theme.dim
        }
    }

    var torSubtitle: String {
        switch self {
        case .train: "Primed for a quality session"
        case .goEasy: "Keep it light — active recovery"
        case .rest: "Recovery comes first today"
        case .insufficientData: "Collecting your baseline"
        }
    }

    var cardTitle: String {
        switch self {
        case .train: "Train"
        case .goEasy: "Go Easy"
        case .rest: "Rest"
        case .insufficientData: "Building Your Baseline"
        }
    }

    var bannerWord: String {
        switch self {
        case .train: "Train"
        case .goEasy: "Go easy"
        case .rest: "Rest"
        case .insufficientData: "Baseline"
        }
    }

    var bannerSymbol: String {
        switch self {
        case .train: "figure.run"
        case .goEasy: "tortoise"
        case .rest: "moon.zzz"
        case .insufficientData: "chart.line.uptrend.xyaxis"
        }
    }
}
