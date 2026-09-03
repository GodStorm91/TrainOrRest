import XCTest
import SwiftData
@testable import TrainOrRest

final class RunHistorySummaryTests: XCTestCase {
    private func activity(km: Double?, seconds: Double) -> CompletedActivity {
        CompletedActivity(
            hkUUID: UUID(),
            date: .now,
            distanceMeters: km.map { $0 * 1000 },
            durationSeconds: seconds,
            avgHeartRate: nil,
            maxHeartRate: nil,
            avgPaceSecondsPerKm: nil,
            sourceName: "Test"
        )
    }

    func testEmptyIsZeroed() {
        let s = RunHistorySummary(activities: [])
        XCTAssertEqual(s.runCount, 0)
        XCTAssertEqual(s.totalDistanceMeters, 0)
        XCTAssertNil(s.averagePaceSecondsPerKm)
        XCTAssertNil(s.longestDistanceMeters)
    }

    func testAggregatesDistanceCountAndLongest() {
        let s = RunHistorySummary(activities: [
            activity(km: 5, seconds: 1500),
            activity(km: 10, seconds: 3000),
            activity(km: 21, seconds: 7200),
        ])
        XCTAssertEqual(s.runCount, 3)
        XCTAssertEqual(s.totalDistanceMeters, 36_000, accuracy: 0.001)
        XCTAssertEqual(s.longestDistanceMeters ?? 0, 21_000, accuracy: 0.001)
        XCTAssertEqual(s.totalDurationSeconds, 11_700, accuracy: 0.001)
    }

    func testAveragePaceIsDistanceWeighted() {
        // 5 km in 1500 s (300 s/km) + 5 km in 2000 s (400 s/km) → 3500 s / 10 km = 350 s/km.
        let s = RunHistorySummary(activities: [
            activity(km: 5, seconds: 1500),
            activity(km: 5, seconds: 2000),
        ])
        XCTAssertEqual(s.averagePaceSecondsPerKm ?? 0, 350, accuracy: 0.001)
    }

    func testRunsWithoutDistanceExcludedFromPaceButCountedInRunCount() {
        let s = RunHistorySummary(activities: [
            activity(km: 5, seconds: 1500),
            activity(km: nil, seconds: 900),
        ])
        XCTAssertEqual(s.runCount, 2)
        XCTAssertEqual(s.averagePaceSecondsPerKm ?? 0, 300, accuracy: 0.001)
    }
}
