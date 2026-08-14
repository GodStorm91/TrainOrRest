import Foundation
import SwiftData

/// One row per day: the readiness verdict, its reasons, and the input
/// values it was computed from. Recomputed (overwritten) on each sync as
/// fresher data lands; `notifiedAt` guards the once-daily notification.
@Model
final class DailyReadiness {
    @Attribute(.unique) var date: Date
    var verdictRaw: String
    var score: Int?
    var reasons: [String]
    var hedged: Bool = false
    var primaryRuleRaw: String?
    var corroboratedFlagCount: Int = 0
    var baselineDayCount: Int
    var hrvMean7: Double?
    var hrvMean28: Double?
    var hrvBaseline: Double?
    var hrvSD: Double?
    var rhrMean7: Double?
    var rhrMean28: Double?
    var rhrBaseline: Double?
    var rhrSD: Double?
    var sleepLastNight: Double?
    var sleepMean14: Double?
    var acuteChronicRatio: Double?
    var computedAt: Date
    var notifiedAt: Date?

    init(date: Date, assessment: ReadinessAssessment, computedAt: Date) {
        self.date = date
        self.verdictRaw = assessment.verdict.rawValue
        self.score = assessment.score
        self.reasons = assessment.reasons
        self.hedged = assessment.hedged
        self.primaryRuleRaw = assessment.primaryRule?.rawValue
        self.corroboratedFlagCount = assessment.corroboratedFlagCount
        self.baselineDayCount = assessment.baselineDayCount
        self.hrvMean7 = assessment.snapshot.hrvMean7
        self.hrvMean28 = assessment.snapshot.hrvMean28
        self.hrvBaseline = assessment.snapshot.hrvBaseline
        self.hrvSD = assessment.snapshot.hrvSD
        self.rhrMean7 = assessment.snapshot.rhrMean7
        self.rhrMean28 = assessment.snapshot.rhrMean28
        self.rhrBaseline = assessment.snapshot.rhrBaseline
        self.rhrSD = assessment.snapshot.rhrSD
        self.sleepLastNight = assessment.snapshot.sleepLastNight
        self.sleepMean14 = assessment.snapshot.sleepMean14
        self.acuteChronicRatio = assessment.snapshot.acuteChronicRatio
        self.computedAt = computedAt
        self.notifiedAt = nil
    }

    var verdict: ReadinessVerdict {
        ReadinessVerdict(rawValue: verdictRaw) ?? .insufficientData
    }

    var primaryRule: ReadinessRule? {
        get { primaryRuleRaw.flatMap(ReadinessRule.init(rawValue:)) }
        set { primaryRuleRaw = newValue?.rawValue }
    }

    func update(from assessment: ReadinessAssessment, computedAt: Date) {
        verdictRaw = assessment.verdict.rawValue
        score = assessment.score
        reasons = assessment.reasons
        hedged = assessment.hedged
        primaryRuleRaw = assessment.primaryRule?.rawValue
        corroboratedFlagCount = assessment.corroboratedFlagCount
        baselineDayCount = assessment.baselineDayCount
        hrvMean7 = assessment.snapshot.hrvMean7
        hrvMean28 = assessment.snapshot.hrvMean28
        hrvBaseline = assessment.snapshot.hrvBaseline
        hrvSD = assessment.snapshot.hrvSD
        rhrMean7 = assessment.snapshot.rhrMean7
        rhrMean28 = assessment.snapshot.rhrMean28
        rhrBaseline = assessment.snapshot.rhrBaseline
        rhrSD = assessment.snapshot.rhrSD
        sleepLastNight = assessment.snapshot.sleepLastNight
        sleepMean14 = assessment.snapshot.sleepMean14
        acuteChronicRatio = assessment.snapshot.acuteChronicRatio
        self.computedAt = computedAt
    }
}
