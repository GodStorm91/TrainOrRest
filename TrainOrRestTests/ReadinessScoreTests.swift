import XCTest
@testable import TrainOrRest

final class ReadinessScoreTests: XCTestCase {
    private func snapshot(
        hrv7: Double? = nil, hrv28: Double? = nil,
        rhr7: Double? = nil, rhr28: Double? = nil,
        sleep: Double? = nil, acwr: Double? = nil
    ) -> ReadinessAssessment.Snapshot {
        .init(hrvMean7: hrv7, hrvMean28: hrv28, rhrMean7: rhr7, rhrMean28: rhr28,
              sleepLastNight: sleep, sleepMean14: nil, acuteChronicRatio: acwr)
    }

    func testInsufficientDataHasNoScore() {
        XCTAssertNil(ReadinessScore.score(snapshot: snapshot(), verdict: .insufficientData))
    }

    func testScoreAlwaysWithinVerdictBand() {
        // Strong signals but forced to a rest verdict → score stays in rest band.
        let strong = snapshot(hrv7: 70, hrv28: 55, rhr7: 45, rhr28: 50, sleep: 8, acwr: 1.0)
        let score = ReadinessScore.score(snapshot: strong, verdict: .rest)!
        XCTAssertTrue((12...49).contains(score), "got \(score)")
    }

    func testTrainVerdictLandsInTrainBand() {
        let good = snapshot(hrv7: 62, hrv28: 55, rhr7: 47, rhr28: 50, sleep: 7.8, acwr: 1.0)
        let score = ReadinessScore.score(snapshot: good, verdict: .train)!
        XCTAssertTrue((70...100).contains(score), "got \(score)")
    }

    func testGoEasyVerdictLandsInEasyBand() {
        let mixed = snapshot(hrv7: 50, hrv28: 55, rhr7: 52, rhr28: 50, sleep: 6, acwr: 1.2)
        let score = ReadinessScore.score(snapshot: mixed, verdict: .goEasy)!
        XCTAssertTrue((50...69).contains(score), "got \(score)")
    }

    func testBetterSignalsScoreHigherWithinBand() {
        let ok = snapshot(hrv7: 56, hrv28: 55, rhr7: 50, rhr28: 50, sleep: 7, acwr: 1.0)
        let great = snapshot(hrv7: 66, hrv28: 55, rhr7: 45, rhr28: 50, sleep: 8, acwr: 1.0)
        let a = ReadinessScore.score(snapshot: ok, verdict: .train)!
        let b = ReadinessScore.score(snapshot: great, verdict: .train)!
        XCTAssertGreaterThanOrEqual(b, a)
    }

    func testMissingSignalsFallBackToBand() {
        let score = ReadinessScore.score(snapshot: snapshot(), verdict: .train)!
        XCTAssertTrue((70...100).contains(score))
    }
}
