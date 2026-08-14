import XCTest
@testable import TrainOrRest

final class ReadinessEngineTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 8)

    private func wellness(overrides: [Int: (hrv: Double?, rhr: Double?, sleep: Double?)] = [:]) -> [WellnessSample] {
        (0..<60).map { daysBack in
            let baseHRV = 60 + Double((daysBack % 5) - 2)
            let baseRHR = 48 + Double((daysBack % 5) - 2)
            let override = overrides[daysBack]
            return WellnessSample(
                date: day(daysBack),
                hrvSDNN: override?.hrv ?? baseHRV,
                restingHeartRate: override?.rhr ?? baseRHR,
                sleepHours: override?.sleep ?? 7.5
            )
        }
    }

    private func steadyLoads(days: Int = 35, load: Double = 60) -> [(date: Date, load: Double)] {
        (0..<days).map { daysBack in
            (date: day(daysBack), load: load)
        }
    }

    private func rampingLoads() -> [(date: Date, load: Double)] {
        (0..<35).map { daysBack in
            (date: day(daysBack), load: daysBack < 7 ? 120 : 40)
        }
    }

    private func assess(
        _ wellness: [WellnessSample],
        loads: [(date: Date, load: Double)] = [],
        checkIns: [CheckInSignal] = [],
        disputedMetrics: Set<ReadinessRule> = []
    ) -> ReadinessAssessment {
        ReadinessEngine.assess(
            wellness: wellness,
            loads: loads,
            today: today,
            calendar: calendar,
            checkIns: checkIns,
            disputedMetrics: disputedMetrics
        )
    }

    private func day(_ daysBack: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!
    }

    // MARK: - Baseline verdicts

    func testHealthyDataYieldsTrain() {
        let assessment = assess(wellness(), loads: steadyLoads())

        XCTAssertEqual(assessment.verdict, .train)
        XCTAssertFalse(assessment.hedged)
        XCTAssertTrue(assessment.reasons.isEmpty)
        XCTAssertEqual(assessment.baselineDayCount, 60)
        XCTAssertEqual(assessment.snapshot.hrvMean28, assessment.snapshot.hrvBaseline)
        XCTAssertEqual(assessment.snapshot.rhrMean28, assessment.snapshot.rhrBaseline)
    }

    func testSingleDeepHRVLowYieldsTrainHedged() {
        let samples = wellness(overrides: [
            0: (hrv: 54, rhr: nil, sleep: nil),
            1: (hrv: 54, rhr: nil, sleep: nil),
            2: (hrv: 54, rhr: nil, sleep: nil)
        ])

        let assessment = assess(samples, loads: steadyLoads())

        XCTAssertEqual(assessment.verdict, .train)
        XCTAssertTrue(assessment.hedged)
        XCTAssertEqual(assessment.reasons.count, 1)
        XCTAssertTrue(assessment.reasons[0].contains("HRV"))
    }

    func testPersistentHRVLowAndRHRHighYieldsGoEasy() {
        let samples = wellness(overrides: [
            0: (hrv: 54, rhr: 56, sleep: nil),
            1: (hrv: 54, rhr: 56, sleep: nil),
            2: (hrv: 54, rhr: 56, sleep: nil)
        ])

        let assessment = assess(samples, loads: steadyLoads())

        XCTAssertEqual(assessment.verdict, .goEasy)
        XCTAssertFalse(assessment.hedged)
        XCTAssertEqual(assessment.reasons.count, 2)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("HRV") })
        XCTAssertTrue(assessment.reasons.contains { $0.contains("Resting HR") })
    }

    func testThreePersistentFlagsYieldRest() {
        let samples = wellness(overrides: [
            0: (hrv: 54, rhr: 56, sleep: 4.8),
            1: (hrv: 54, rhr: 56, sleep: nil),
            2: (hrv: 54, rhr: 56, sleep: nil)
        ])

        let assessment = assess(samples, loads: steadyLoads())

        XCTAssertEqual(assessment.verdict, .rest)
        XCTAssertFalse(assessment.hedged)
        XCTAssertEqual(assessment.reasons.count, 3)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("Slept") })
    }

    func testSingleDayTwoFlagSpikeYieldsTrainHedgedWithoutPersistence() {
        let samples = wellness(overrides: [
            0: (hrv: 35, rhr: 72, sleep: nil)
        ])

        let assessment = assess(samples, loads: steadyLoads())

        XCTAssertEqual(assessment.verdict, .train)
        XCTAssertTrue(assessment.hedged)
        XCTAssertEqual(assessment.reasons.count, 2)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("HRV") })
        XCTAssertTrue(assessment.reasons.contains { $0.contains("Resting HR") })
    }

    func testIllChipForcesRest() {
        let assessment = assess(wellness(), loads: steadyLoads(), checkIns: [.ill])

        XCTAssertEqual(assessment.verdict, .rest)
        XCTAssertFalse(assessment.hedged)
        XCTAssertEqual(assessment.reasons, ["Reported illness"])
    }

    func testDisputedHRVDoesNotForceRestWithHighLoad() {
        let samples = wellness(overrides: [
            0: (hrv: 54, rhr: nil, sleep: nil),
            1: (hrv: 54, rhr: nil, sleep: nil),
            2: (hrv: 54, rhr: nil, sleep: nil)
        ])
        let confirmed = assess(samples, loads: rampingLoads())
        let disputed = assess(samples, loads: rampingLoads(), disputedMetrics: [.hrv])

        XCTAssertEqual(confirmed.verdict, .rest)
        XCTAssertEqual(disputed.verdict, .train)
        XCTAssertTrue(disputed.hedged)
        XCTAssertEqual(disputed.corroboratedFlagCount, 1)
        XCTAssertEqual(disputed.primaryRule, .load)
        XCTAssertTrue(disputed.reasons.contains("HRV disputed between sources — not counted"))
        XCTAssertTrue(disputed.reasons.contains { $0.contains("Training load") })
    }

    // MARK: - Missing data

    func testUnderFourteenDaysIsInsufficient() {
        let samples = Array(wellness().prefix(13))

        let assessment = assess(samples, loads: steadyLoads())

        XCTAssertEqual(assessment.verdict, .insufficientData)
        XCTAssertFalse(assessment.hedged)
        XCTAssertEqual(assessment.baselineDayCount, 13)
        XCTAssertNil(assessment.score)
    }

    func testNoDataAtAllIsInsufficient() {
        let assessment = assess([], loads: [])

        XCTAssertEqual(assessment.verdict, .insufficientData)
        XCTAssertFalse(assessment.hedged)
        XCTAssertEqual(assessment.baselineDayCount, 0)
        XCTAssertNil(assessment.score)
    }

    func testACWRRequiresFullChronicHistory() {
        let shortHistoryLoads = (0..<7).map { daysBack in
            (date: day(daysBack), load: 100.0)
        }

        let assessment = assess(wellness(), loads: shortHistoryLoads)

        XCTAssertNil(assessment.snapshot.acuteChronicRatio)
        XCTAssertEqual(assessment.verdict, .train)
        XCTAssertFalse(assessment.hedged)
        XCTAssertTrue(assessment.reasons.isEmpty)
    }
}
