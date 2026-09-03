import Foundation
import SwiftData

enum ReadinessRule: String, Codable, CaseIterable {
    case hrv
    case rhr
    case sleep
    case load
}

@Model
final class RuleOverride {
    var date: Date
    var ruleRaw: String

    init(date: Date, rule: ReadinessRule) {
        self.date = date
        self.ruleRaw = rule.rawValue
    }

    var rule: ReadinessRule {
        get { ReadinessRule(rawValue: ruleRaw) ?? .hrv }
        set { ruleRaw = newValue.rawValue }
    }
}
