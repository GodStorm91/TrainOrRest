import XCTest
@testable import TrainOrRest

final class CoachTodayEngineHeaderTests: XCTestCase {
    func testHeaderTextReflectsEngineVerdictAndRuleCodes() {
        let readiness = DailyReadiness(
            date: PlanEngineTestSupport.date(2026, 7, 8),
            assessment: ReadinessAssessment(
                verdict: .rest,
                score: 41,
                reasons: ["Rest today."],
                ruleIDs: [.hrvLow, .illness],
                baselineDayCount: 30,
                snapshot: .init(
                    hrvMean7: 44,
                    hrvMean28: 60,
                    rhrMean7: nil,
                    rhrMean28: nil,
                    sleepLastNight: 7,
                    sleepMean14: 7,
                    acuteChronicRatio: 1.0
                )
            ),
            computedAt: PlanEngineTestSupport.date(2026, 7, 8)
        )

        XCTAssertEqual(CoachTodayHeaderText.text(for: readiness), "Engine · Rest · R4 · R7")
        XCTAssertEqual(CoachTodayHeaderText.compactText(for: readiness), "Rest · R4 · R7")
    }

    func testHeaderTextShowsNoVerdictYetWithoutReadiness() {
        XCTAssertEqual(CoachTodayHeaderText.text(for: nil), "Engine · No verdict yet")
        XCTAssertEqual(CoachTodayHeaderText.compactText(for: nil), "No verdict yet")
    }
}
