import XCTest
@testable import TrainOrRest

final class ReadinessRuleCatalogTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 8)

    func testCatalogCodesMatchDesignMappingAndMetadataIsPresent() {
        let expected: [ReadinessRuleID: String] = [
            .rhrElevated: "R1",
            .shortSleep: "R2",
            .loadRamp: "R3",
            .hrvLow: "R4",
            .overreaching: "R5",
            .soreness: "R6",
            .illness: "R7",
            .persistenceHold: "R8",
            .sourceDispute: "R9",
            .overrideWidened: "R10"
        ]

        XCTAssertEqual(ReadinessRuleID.all.count, expected.count)
        XCTAssertEqual(Set(ReadinessRuleID.all.map(\.code)).count, expected.count)

        for id in ReadinessRuleID.all {
            XCTAssertEqual(id.code, expected[id] ?? "")
            XCTAssertFalse(id.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(id.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testEngineAttachesHRVAndRHRCodes() {
        let samples = wellness(overrides: [
            0: (hrv: 54, rhr: 56, sleep: nil),
            1: (hrv: 54, rhr: 56, sleep: nil),
            2: (hrv: 54, rhr: 56, sleep: nil)
        ])

        let assessment = assess(samples, loads: steadyLoads())

        XCTAssertTrue(assessment.ruleIDs.contains(.hrvLow))
        XCTAssertTrue(assessment.ruleIDs.contains(.rhrElevated))
        XCTAssertEqual(Array(assessment.ruleIDs.prefix(2)), [.hrvLow, .rhrElevated])
    }

    func testIllnessOnlyAttachesIllnessCode() {
        let assessment = assess(wellness(), loads: steadyLoads(), checkIns: [.ill])

        XCTAssertEqual(assessment.ruleIDs, [.illness])
    }

    func testDisputedHRVAttachesSourceDisputeCode() {
        let samples = wellness(overrides: [
            0: (hrv: 54, rhr: nil, sleep: nil),
            1: (hrv: 54, rhr: nil, sleep: nil),
            2: (hrv: 54, rhr: nil, sleep: nil)
        ])

        let assessment = assess(samples, loads: steadyLoads(), disputedMetrics: [.hrv])

        XCTAssertTrue(assessment.ruleIDs.contains(.sourceDispute))
        XCTAssertFalse(assessment.ruleIDs.contains(.hrvLow))
    }

    func testSingleDayTwoFlagSpikeBlockedByPersistenceAttachesPersistenceHoldCode() {
        let samples = wellness(overrides: [
            0: (hrv: 35, rhr: 72, sleep: nil)
        ])

        let assessment = assess(samples, loads: steadyLoads())

        XCTAssertTrue(assessment.ruleIDs.contains(.persistenceHold))
    }

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
}
