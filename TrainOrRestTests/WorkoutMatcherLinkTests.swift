import XCTest
@testable import TrainOrRest

final class WorkoutMatcherLinkTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    private func planned(
        _ id: UUID = UUID(),
        expectedMinutes: Double?,
        dismissedActivityIDs: Set<UUID> = []
    ) -> WorkoutMatcher.PlannedRef {
        WorkoutMatcher.PlannedRef(
            id: id,
            date: PlanEngineTestSupport.date(2026, 7, 6),
            expectedDurationSeconds: expectedMinutes.map { $0 * 60 },
            dismissedActivityIDs: dismissedActivityIDs
        )
    }

    private func activity(_ id: UUID = UUID(), minutes: Double) -> WorkoutMatcher.ActivityRef {
        WorkoutMatcher.ActivityRef(
            id: id,
            date: PlanEngineTestSupport.date(2026, 7, 6, hour: 7),
            durationSeconds: minutes * 60
        )
    }

    func testFirstPassSkipsDismissedActivity() {
        let dismissed = activity(minutes: 50)
        let eligible = activity(minutes: 53)
        let workout = planned(expectedMinutes: 50, dismissedActivityIDs: [dismissed.id])

        let matches = WorkoutMatcher.matches(
            planned: [workout], activities: [dismissed, eligible], calendar: calendar
        )

        XCTAssertEqual(matches[workout.id], eligible.id)
    }

    func testLoneRunFallbackSkipsDismissedActivity() {
        let run = activity(minutes: 125)
        let workout = planned(expectedMinutes: 50, dismissedActivityIDs: [run.id])

        let matches = WorkoutMatcher.matches(planned: [workout], activities: [run], calendar: calendar)

        XCTAssertTrue(matches.isEmpty)
    }

    func testSuggestionChoosesClosestDurationWithoutToleranceCap() {
        let workout = planned(expectedMinutes: 50)
        let farther = activity(minutes: 80)
        let closest = activity(minutes: 62)

        let suggestion = WorkoutMatcher.suggestion(for: workout, among: [farther, closest])

        XCTAssertEqual(suggestion, closest.id)
    }

    func testSuggestionWithoutExpectedDurationChoosesLongestRun() {
        let workout = planned(expectedMinutes: nil)
        let shorter = activity(minutes: 35)
        let longer = activity(minutes: 70)

        let suggestion = WorkoutMatcher.suggestion(for: workout, among: [shorter, longer])

        XCTAssertEqual(suggestion, longer.id)
    }

    func testSuggestionWithoutExpectedDurationBreaksDurationTiesByID() {
        let workout = planned(expectedMinutes: nil)
        let higherID = activity(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, minutes: 70)
        let lowerID = activity(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, minutes: 70)

        let suggestion = WorkoutMatcher.suggestion(for: workout, among: [higherID, lowerID])

        XCTAssertEqual(suggestion, lowerID.id)
    }
}
