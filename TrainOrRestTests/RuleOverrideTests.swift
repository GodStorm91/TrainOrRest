import XCTest
@testable import TrainOrRest

final class RuleOverrideTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 8)

    func testTwoRecentHRVOverridesWidenThreshold() {
        let withoutOverrides = assess(borderlineHRVWellness())
        let withOverrides = assess(
            borderlineHRVWellness(),
            overrides: [
                (date: day(1), rule: .hrv),
                (date: day(6), rule: .hrv)
            ]
        )

        XCTAssertEqual(withoutOverrides.verdict, .train)
        XCTAssertTrue(withoutOverrides.hedged)
        XCTAssertEqual(withoutOverrides.corroboratedFlagCount, 1)
        XCTAssertEqual(withoutOverrides.primaryRule, .hrv)
        XCTAssertTrue(withoutOverrides.reasons.contains { $0.contains("HRV") })

        XCTAssertEqual(withOverrides.verdict, .train)
        XCTAssertFalse(withOverrides.hedged)
        XCTAssertEqual(withOverrides.corroboratedFlagCount, 0)
        XCTAssertNil(withOverrides.primaryRule)
        XCTAssertFalse(withOverrides.reasons.contains { $0.contains("HRV") })
    }

    func testOverridesOlderThanFourteenDaysDoNotWidenThreshold() {
        let assessment = assess(
            borderlineHRVWellness(),
            overrides: [
                (date: day(15), rule: .hrv),
                (date: day(20), rule: .hrv)
            ]
        )

        XCTAssertEqual(assessment.verdict, .train)
        XCTAssertTrue(assessment.hedged)
        XCTAssertEqual(assessment.corroboratedFlagCount, 1)
        XCTAssertEqual(assessment.primaryRule, .hrv)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("HRV") })
    }

    func testSingleDaySoreDoesNotAddAFlag() {
        let assessment = assess(
            healthyWellness(),
            checkIns: [.sore],
            checkInHistory: [(date: day(0), signals: [.sore])]
        )

        XCTAssertEqual(assessment.verdict, .train)
        XCTAssertFalse(assessment.hedged)
        XCTAssertEqual(assessment.corroboratedFlagCount, 0)
        XCTAssertNil(assessment.primaryRule)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("watching for a second day") })
    }

    func testTwoConsecutiveSoreDaysContributeAFlagWhenCombinedWithHRV() {
        let singleDaySore = assess(
            borderlineHRVWellness(),
            checkIns: [.sore],
            checkInHistory: [(date: day(0), signals: [.sore])]
        )
        let twoDaySore = assess(
            borderlineHRVWellness(),
            checkIns: [.sore],
            checkInHistory: [
                (date: day(0), signals: [.sore]),
                (date: day(1), signals: [.sore])
            ]
        )

        XCTAssertEqual(singleDaySore.verdict, .train)
        XCTAssertTrue(singleDaySore.hedged)
        XCTAssertEqual(singleDaySore.corroboratedFlagCount, 1)

        XCTAssertEqual(twoDaySore.verdict, .goEasy)
        XCTAssertFalse(twoDaySore.hedged)
        XCTAssertEqual(twoDaySore.corroboratedFlagCount, 2)
        XCTAssertEqual(twoDaySore.primaryRule, .hrv)
        XCTAssertTrue(twoDaySore.reasons.contains { $0.contains("2 consecutive days") })
    }

    private func assess(
        _ wellness: [WellnessSample],
        checkIns: [CheckInSignal] = [],
        overrides: [(date: Date, rule: ReadinessRule)] = [],
        checkInHistory: [(date: Date, signals: [CheckInSignal])] = []
    ) -> ReadinessAssessment {
        ReadinessEngine.assess(
            wellness: wellness,
            loads: [],
            today: today,
            calendar: calendar,
            checkIns: checkIns,
            overrides: overrides,
            checkInHistory: checkInHistory
        )
    }

    private func healthyWellness() -> [WellnessSample] {
        (0..<60).map { daysBack in
            WellnessSample(
                date: day(daysBack),
                hrvSDNN: 60,
                restingHeartRate: 48,
                sleepHours: 7.5
            )
        }
    }

    private func borderlineHRVWellness() -> [WellnessSample] {
        (0..<60).map { daysBack in
            let hrv: Double
            if daysBack < 3 {
                hrv = 57.75
            } else if daysBack < 43 {
                hrv = 60
            } else {
                hrv = 64
            }
            return WellnessSample(
                date: day(daysBack),
                hrvSDNN: hrv,
                restingHeartRate: 48,
                sleepHours: 7.5
            )
        }
    }

    private func day(_ daysBack: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!
    }
}
