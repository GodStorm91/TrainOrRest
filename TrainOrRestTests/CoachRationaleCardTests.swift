import XCTest
@testable import TrainOrRest

final class CoachRationaleCardTests: XCTestCase {
    private let today = PlanEngineTestSupport.date(2026, 7, 8)

    func testReadinessRationaleBuilderUsesEngineVerdictSignalsAndRules() {
        let readiness = DailyReadiness(
            date: today,
            assessment: ReadinessAssessment(
                verdict: .rest,
                score: 36,
                reasons: ["HRV is below baseline and sleep was short."],
                ruleIDs: [.hrvLow, .shortSleep, .loadRamp],
                baselineDayCount: 42,
                snapshot: .init(
                    hrvMean7: 44,
                    hrvMean28: 60,
                    rhrMean7: 53,
                    rhrMean28: 48,
                    sleepLastNight: 5.5,
                    sleepMean14: 7.25,
                    acuteChronicRatio: 1.36
                )
            ),
            computedAt: today
        )

        let rationale = ReadinessRationale(from: readiness)

        XCTAssertEqual(rationale.verdict, .rest)
        XCTAssertEqual(rationale.score, 36)
        XCTAssertEqual(rationale.ruleIDs, [.hrvLow, .shortSleep, .loadRamp])
        XCTAssertEqual(rationale.signals.map(\.id), ["hrv", "sleep", "load"])
        XCTAssertEqual(rationale.signals[0].value, "7-day 44 ms vs baseline 60 ms")
        XCTAssertEqual(rationale.signals[1].value, "5h 30m last night vs 7h 15m 14-day mean")
        XCTAssertEqual(rationale.signals[2].value, "1.36 acute:chronic load")
        XCTAssertEqual(rationale.summary, "HRV is below baseline and sleep was short.")
        XCTAssertEqual(rationale.computedAt, today)
    }

    func testCoachWorkoutSummaryBuilderFormatsCoreWorkoutFields() {
        let spec = PlannedWorkoutSpec(
            date: today,
            kind: .tempo,
            distanceKm: 9,
            paceBand: PaceBand(fastSecondsPerKm: 265, slowSecondsPerKm: 285),
            details: "2 km easy + 5 km threshold + 2 km easy"
        )

        let summary = CoachWorkoutSummary(from: spec)

        XCTAssertEqual(summary.title, "Tempo")
        XCTAssertEqual(summary.targets, ["2 km easy + 5 km threshold + 2 km easy"])
        XCTAssertEqual(summary.distance, "9.00 km")
        XCTAssertEqual(summary.duration, "41:15")
        XCTAssertEqual(summary.paceBand, "4:25–4:45 /km")
        XCTAssertEqual(summary.symbolName, "gauge.with.needle")
    }
}
