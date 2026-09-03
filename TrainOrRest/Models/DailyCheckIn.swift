import Foundation
import SwiftData

enum CheckInSignalRole {
    case standalone
    case corroborator
}

enum CheckInSignal: String, CaseIterable, Codable {
    case sore
    case ill
    case poorSleep
    case travel
    case alcohol
    case stress
    case heat

    var displayName: String {
        switch self {
        case .sore: "Sore"
        case .ill: "Ill"
        case .poorSleep: "Poor sleep"
        case .travel: "Travel"
        case .alcohol: "Alcohol"
        case .stress: "Stress"
        case .heat: "Heat"
        }
    }

    var symbolName: String {
        switch self {
        case .sore: "figure.strengthtraining.traditional"
        case .ill: "cross.case"
        case .poorSleep: "bed.double"
        case .travel: "airplane"
        case .alcohol: "wineglass"
        case .stress: "exclamationmark.bubble"
        case .heat: "thermometer.sun"
        }
    }

    var role: CheckInSignalRole {
        switch self {
        case .ill, .sore:
            .standalone
        case .travel, .alcohol, .stress, .heat, .poorSleep:
            .corroborator
        }
    }
}

@Model
final class DailyCheckIn {
    @Attribute(.unique) var date: Date
    var signalsRaw: [String]

    init(date: Date, signals: [CheckInSignal] = []) {
        self.date = date
        self.signalsRaw = signals.map(\.rawValue)
    }

    var signals: [CheckInSignal] {
        get {
            let selected = Set(signalsRaw.compactMap(CheckInSignal.init(rawValue:)))
            return CheckInSignal.allCases.filter { selected.contains($0) }
        }
        set {
            signalsRaw = newValue.map(\.rawValue)
        }
    }
}
