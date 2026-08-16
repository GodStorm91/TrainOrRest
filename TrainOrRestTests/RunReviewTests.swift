import XCTest
@testable import TrainOrRest

final class RunReviewTests: XCTestCase {
    func testOnPlanReviewWhenDistanceAndPaceMatch() {
        let review = RunReview.make(
            activityDistanceMeters: 10_100,
            activityDurationSeconds: 3_000,
            activityPaceSecondsPerKm: 300,
            avgHeartRate: 142,
            plannedDistanceKm: 10,
            plannedPaceBand: PaceBand(fastSecondsPerKm: 295, slowSecondsPerKm: 305),
            plannedDurationSeconds: 3_000
        )

        XCTAssertEqual(review.verdict, .onPlan)
        XCTAssertTrue(review.bullets.contains("Distance landed on plan"))
        XCTAssertTrue(review.bullets.contains("Pace was right in range"))
    }

    func testOvercookedReviewWhenRunIsMuchFaster() {
        let review = RunReview.make(
            activityDistanceMeters: 10_000,
            activityDurationSeconds: 2_700,
            activityPaceSecondsPerKm: 270,
            avgHeartRate: 150,
            plannedDistanceKm: 10,
            plannedPaceBand: PaceBand(fastSecondsPerKm: 295, slowSecondsPerKm: 305),
            plannedDurationSeconds: 3_000
        )

        XCTAssertEqual(review.verdict, .overcooked)
        XCTAssertTrue(review.bullets.contains("0:30 /km faster than planned"))
    }

    func testUnmatchedRunStillGetsUsefulReview() {
        let review = RunReview.make(
            activityDistanceMeters: 5_000,
            activityDurationSeconds: 1_600,
            activityPaceSecondsPerKm: 320,
            avgHeartRate: 138,
            plannedDistanceKm: nil,
            plannedPaceBand: nil,
            plannedDurationSeconds: nil
        )

        XCTAssertEqual(review.verdict, .unmatched)
        XCTAssertTrue(review.recoveryNote.contains("Synced from Garmin"))
    }
}
