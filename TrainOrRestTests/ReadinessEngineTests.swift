import XCTest
@testable import TrainOrRest

final class ReadinessEngineTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 8)

    /// 28 days of healthy, stable wellness ending today.
    private func healthyWellness() -> [WellnessSample] {
        (0..<28).map { daysBack in
            WellnessSample(
                date: calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!,
                hrvSDNN: 60,
                restingHeartRate: 48,
                sleepHours: 7.5
            )
        }
    }

    /// Steady moderate load history over `days` days (rest every 2nd day).
    private func steadyLoads(days: Int = 35) -> [(date: Date, load: Double)] {
        stride(from: 0, to: days, by: 2).map { daysBack in
            (
                date: calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!,
                load: 60.0
            )
        }
    }

    private func assess(
        _ wellness: [WellnessSample],
        loads: [(date: Date, load: Double)] = []
    ) -> ReadinessAssessment {
        ReadinessEngine.assess(wellness: wellness, loads: loads, today: today, calendar: calendar)
    }

    // MARK: - Verdict matrix

    func testHealthyDataYieldsTrain() {
        let assessment = assess(healthyWellness(), loads: steadyLoads())
        XCTAssertEqual(assessment.verdict, .train)
        XCTAssertTrue(assessment.reasons.isEmpty)
    }

    func testSuppressedHRVAloneYieldsGoEasy() {
        var wellness = healthyWellness()
        // Last 7 days HRV well below the 28-day baseline.
        for index in wellness.indices where wellness[index].date > calendar.date(byAdding: .day, value: -7, to: today)! {
            wellness[index].hrvSDNN = 40
        }
        let assessment = assess(wellness, loads: steadyLoads())
        XCTAssertEqual(assessment.verdict, .goEasy)
        XCTAssertEqual(assessment.reasons.count, 1)
        XCTAssertTrue(assessment.reasons[0].contains("HRV"))
    }

    func testElevatedRestingHRAloneYieldsGoEasy() {
        var wellness = healthyWellness()
        for index in wellness.indices where wellness[index].date > calendar.date(byAdding: .day, value: -7, to: today)! {
            wellness[index].restingHeartRate = 56
        }
        let assessment = assess(wellness, loads: steadyLoads())
        XCTAssertEqual(assessment.verdict, .goEasy)
        XCTAssertTrue(assessment.reasons[0].contains("Resting HR"))
    }

    func testShortSleepLastNightAloneYieldsGoEasy() {
        var wellness = healthyWellness()
        let todayIndex = wellness.firstIndex { calendar.isDate($0.date, inSameDayAs: today) }!
        wellness[todayIndex].sleepHours = 4.5
        let assessment = assess(wellness, loads: steadyLoads())
        XCTAssertEqual(assessment.verdict, .goEasy)
        XCTAssertTrue(assessment.reasons[0].contains("Slept"))
    }

    func testHighACWRAloneYieldsGoEasy() {
        // Chronic base ~15/day doubled over the last week.
        var loads = steadyLoads().map { (date: $0.date, load: 30.0) }
        for daysBack in 0..<7 {
            loads.append((
                date: calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!,
                load: 60.0
            ))
        }
        let assessment = assess(healthyWellness(), loads: loads)
        XCTAssertEqual(assessment.verdict, .goEasy)
        XCTAssertTrue(assessment.reasons[0].contains("load"))
    }

    func testTwoFlagsYieldRest() {
        var wellness = healthyWellness()
        let todayIndex = wellness.firstIndex { calendar.isDate($0.date, inSameDayAs: today) }!
        wellness[todayIndex].sleepHours = 4
        for index in wellness.indices where wellness[index].date > calendar.date(byAdding: .day, value: -7, to: today)! {
            wellness[index].restingHeartRate = 57
        }
        let assessment = assess(wellness, loads: steadyLoads())
        XCTAssertEqual(assessment.verdict, .rest)
        XCTAssertEqual(assessment.reasons.count, 2)
    }

    // MARK: - Missing data

    func testMissingSignalSkipsItsFlag() {
        var wellness = healthyWellness()
        for index in wellness.indices {
            wellness[index].hrvSDNN = nil // no HRV at all
        }
        let assessment = assess(wellness, loads: steadyLoads())
        XCTAssertEqual(assessment.verdict, .train)
        XCTAssertNil(assessment.snapshot.hrvMean7)
    }

    func testUnderFourteenDaysIsInsufficient() {
        let wellness = healthyWellness().filter {
            $0.date > calendar.date(byAdding: .day, value: -10, to: today)!
        }
        let assessment = assess(wellness, loads: steadyLoads())
        XCTAssertEqual(assessment.verdict, .insufficientData)
        XCTAssertLessThan(assessment.baselineDayCount, 14)
    }

    func testNoDataAtAllIsInsufficient() {
        let assessment = assess([], loads: [])
        XCTAssertEqual(assessment.verdict, .insufficientData)
        XCTAssertEqual(assessment.baselineDayCount, 0)
    }

    func testACWRRequiresFullChronicHistory() {
        // Only 2 weeks of loads — ACWR must not participate even when spiky.
        var loads: [(date: Date, load: Double)] = []
        for daysBack in 0..<7 {
            loads.append((
                date: calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: today))!,
                load: 100.0
            ))
        }
        let assessment = assess(healthyWellness(), loads: loads)
        XCTAssertNil(assessment.snapshot.acuteChronicRatio)
        XCTAssertEqual(assessment.verdict, .train)
    }
}
