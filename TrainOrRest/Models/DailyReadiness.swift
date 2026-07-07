import Foundation
import SwiftData

/// One row per day: the readiness verdict, its reasons, and the input
/// values it was computed from. Recomputed (overwritten) on each sync as
/// fresher data lands; `notifiedAt` guards the once-daily notification.
@Model
final class DailyReadiness {
    @Attribute(.unique) var date: Date
    var verdictRaw: String
    var reasons: [String]
    var baselineDayCount: Int
    var hrvMean7: Double?
    var hrvMean28: Double?
    var rhrMean7: Double?
    var rhrMean28: Double?
    var sleepLastNight: Double?
    var sleepMean14: Double?
    var acuteChronicRatio: Double?
    var computedAt: Date
    var notifiedAt: Date?

    init(date: Date, assessment: ReadinessAssessment, computedAt: Date) {
        self.date = date
        self.verdictRaw = assessment.verdict.rawValue
        self.reasons = assessment.reasons
        self.baselineDayCount = assessment.baselineDayCount
        self.hrvMean7 = assessment.snapshot.hrvMean7
        self.hrvMean28 = assessment.snapshot.hrvMean28
        self.rhrMean7 = assessment.snapshot.rhrMean7
        self.rhrMean28 = assessment.snapshot.rhrMean28
        self.sleepLastNight = assessment.snapshot.sleepLastNight
        self.sleepMean14 = assessment.snapshot.sleepMean14
        self.acuteChronicRatio = assessment.snapshot.acuteChronicRatio
        self.computedAt = computedAt
        self.notifiedAt = nil
    }

    var verdict: ReadinessVerdict {
        ReadinessVerdict(rawValue: verdictRaw) ?? .insufficientData
    }

    func update(from assessment: ReadinessAssessment, computedAt: Date) {
        verdictRaw = assessment.verdict.rawValue
        reasons = assessment.reasons
        baselineDayCount = assessment.baselineDayCount
        hrvMean7 = assessment.snapshot.hrvMean7
        hrvMean28 = assessment.snapshot.hrvMean28
        rhrMean7 = assessment.snapshot.rhrMean7
        rhrMean28 = assessment.snapshot.rhrMean28
        sleepLastNight = assessment.snapshot.sleepLastNight
        sleepMean14 = assessment.snapshot.sleepMean14
        acuteChronicRatio = assessment.snapshot.acuteChronicRatio
        self.computedAt = computedAt
    }
}
