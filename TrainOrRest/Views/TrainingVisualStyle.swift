import SwiftUI

enum TrainingVisualStyle {
    static let easy = Color.teal
    static let long = Color.blue
    static let tempo = Color.orange
    static let intervals = Color.orange
    static let race = Color.red
    static let recovery = Color.teal
    static let sleep = Color.blue
    static let heart = Color.red
    static let oxygen = Color.teal

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

extension CompletedActivity {
    var effortColor: Color {
        if let avgHeartRate, avgHeartRate >= 165 {
            return TrainingVisualStyle.intervals
        }
        if let avgPaceSecondsPerKm, avgPaceSecondsPerKm < 300 {
            return TrainingVisualStyle.tempo
        }
        if let distanceMeters, distanceMeters >= 12_000 {
            return TrainingVisualStyle.long
        }
        return TrainingVisualStyle.easy
    }
}
