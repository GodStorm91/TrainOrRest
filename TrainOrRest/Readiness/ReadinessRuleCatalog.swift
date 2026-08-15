import Foundation

enum ReadinessRuleID: String, Codable, CaseIterable {
    case rhrElevated = "R1"
    case shortSleep = "R2"
    case loadRamp = "R3"
    case hrvLow = "R4"
    case overreaching = "R5"
    case soreness = "R6"
    case illness = "R7"
    case persistenceHold = "R8"
    case sourceDispute = "R9"
    case overrideWidened = "R10"

    var code: String { rawValue }

    var title: String {
        switch self {
        case .rhrElevated:
            return "Resting heart rate elevated"
        case .shortSleep:
            return "Short sleep"
        case .loadRamp:
            return "Training load ramping"
        case .hrvLow:
            return "HRV below your baseline"
        case .overreaching:
            return "HRV and load both strained"
        case .soreness:
            return "Soreness repeated"
        case .illness:
            return "Illness reported"
        case .persistenceHold:
            return "Held by persistence gate"
        case .sourceDispute:
            return "Source dispute suppressed"
        case .overrideWidened:
            return "Override widened threshold"
        }
    }

    var detail: String {
        switch self {
        case .rhrElevated:
            return "Flags recovery strain when recent resting heart rate is above your personal baseline band."
        case .shortSleep:
            return "Flags recovery strain when last night's sleep is short or sharply below your recent norm."
        case .loadRamp:
            return "Flags risk when recent training load is high compared with your longer-term load."
        case .hrvLow:
            return "Flags recovery strain when recent HRV falls below your personal baseline band."
        case .overreaching:
            return "Recommends more recovery when low HRV appears together with a fast training-load ramp."
        case .soreness:
            return "Caps intensity only after soreness is reported on two consecutive days."
        case .illness:
            return "Recommends rest when you report illness, without requiring sensor confirmation."
        case .persistenceHold:
            return "Keeps a one-day spike from cutting volume until signals persist on two of three days."
        case .sourceDispute:
            return "Suppresses a metric flag when trusted sources disagree enough to make that metric uncertain."
        case .overrideWidened:
            return "Applies recent keep-planned overrides by widening that rule's threshold for this run."
        }
    }

    static var all: [ReadinessRuleID] { allCases }
}
