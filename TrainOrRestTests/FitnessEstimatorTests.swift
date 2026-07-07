import XCTest
@testable import TrainOrRest

final class FitnessEstimatorTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 8)

    func testEstimateFromRegularHistory() throws {
        // 8 weeks × 4 runs of 8 km @ 5:30/km → 32 km/week.
        let samples = PlanEngineTestSupport.history(
            weeks: 8, runsPerWeek: 4, distanceKm: 8, paceSecondsPerKm: 330, endingAt: today
        )
        let profile = try XCTUnwrap(FitnessEstimator.estimate(samples: samples, today: today, calendar: calendar))

        XCTAssertEqual(profile.weeklyVolumeKm, 32, accuracy: 8)
        XCTAssertEqual(profile.volumeTrend, 0, accuracy: 0.25)
        XCTAssertEqual(profile.longestRecentRunKm, 8)
        let expectedVDOT = VDOTTable.vdot(distanceMeters: 8000, timeSeconds: 8 * 330)
        XCTAssertEqual(profile.vdot, expectedVDOT, accuracy: 0.01)
    }

    func testBestEffortDrivesVDOT() throws {
        var samples = PlanEngineTestSupport.history(
            weeks: 8, runsPerWeek: 4, distanceKm: 8, paceSecondsPerKm: 360, endingAt: today
        )
        // One hard 10K parkrun-style effort should set the VDOT.
        let hardEffort = RunSample(
            date: calendar.date(byAdding: .day, value: -10, to: today)!,
            distanceKm: 10,
            durationSeconds: 45 * 60
        )
        samples.append(hardEffort)
        let profile = try XCTUnwrap(FitnessEstimator.estimate(samples: samples, today: today, calendar: calendar))
        let hardVDOT = VDOTTable.vdot(distanceMeters: 10000, timeSeconds: 45 * 60)
        XCTAssertEqual(profile.vdot, hardVDOT, accuracy: 0.01)
    }

    func testColdStartReturnsNil() {
        // Too few runs.
        let sparse = PlanEngineTestSupport.history(
            weeks: 8, runsPerWeek: 0, distanceKm: 8, paceSecondsPerKm: 330, endingAt: today
        )
        XCTAssertNil(FitnessEstimator.estimate(samples: sparse, today: today, calendar: calendar))

        // Enough runs but crammed into under 4 weeks.
        let recent = PlanEngineTestSupport.history(
            weeks: 3, runsPerWeek: 4, distanceKm: 8, paceSecondsPerKm: 330, endingAt: today
        )
        XCTAssertNil(FitnessEstimator.estimate(samples: recent, today: today, calendar: calendar))
    }

    func testShortRunsDoNotQualify() {
        let junk = PlanEngineTestSupport.history(
            weeks: 8, runsPerWeek: 5, distanceKm: 2, paceSecondsPerKm: 330, endingAt: today
        )
        XCTAssertNil(FitnessEstimator.estimate(samples: junk, today: today, calendar: calendar))
    }

    func testComfortablePaceFallback() {
        let profile = FitnessEstimator.profile(comfortablePaceSecondsPerKm: 330, weeklyVolumeKm: 25)
        // Easy pace ≈ 70% VO2max: invert and compare.
        let velocity = 60_000.0 / 330
        let expected = VDOTTable.oxygenCost(velocityMetersPerMinute: velocity) / 0.70
        XCTAssertEqual(profile.vdot, expected, accuracy: 0.01)
        XCTAssertEqual(profile.weeklyVolumeKm, 25)
    }
}
