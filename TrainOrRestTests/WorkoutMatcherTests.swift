import XCTest
@testable import TrainOrRest

final class WorkoutMatcherTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar

    private func planned(_ id: UUID = UUID(), day: Int, expectedMinutes: Double?) -> WorkoutMatcher.PlannedRef {
        WorkoutMatcher.PlannedRef(
            id: id,
            date: PlanEngineTestSupport.date(2026, 7, day),
            expectedDurationSeconds: expectedMinutes.map { $0 * 60 }
        )
    }

    private func activity(_ id: UUID = UUID(), day: Int, minutes: Double, hour: Int = 7) -> WorkoutMatcher.ActivityRef {
        WorkoutMatcher.ActivityRef(
            id: id,
            date: PlanEngineTestSupport.date(2026, 7, day, hour: hour),
            durationSeconds: minutes * 60
        )
    }

    func testDurationWithinToleranceMatches() {
        let workout = planned(day: 6, expectedMinutes: 50)
        let run = activity(day: 6, minutes: 55)
        let matches = WorkoutMatcher.matches(planned: [workout], activities: [run], calendar: calendar)
        XCTAssertEqual(matches[workout.id], run.id)
    }

    func testClosestOfSeveralActivitiesWins() {
        let workout = planned(day: 6, expectedMinutes: 50)
        let short = activity(day: 6, minutes: 35)
        let close = activity(day: 6, minutes: 48)
        let matches = WorkoutMatcher.matches(planned: [workout], activities: [short, close], calendar: calendar)
        XCTAssertEqual(matches[workout.id], close.id)
    }

    func testFarOffDurationFallsBackToLoneRunRule() {
        // 150% deviation is outside tolerance, but it's the only run that day.
        let workout = planned(day: 6, expectedMinutes: 50)
        let run = activity(day: 6, minutes: 125)
        let matches = WorkoutMatcher.matches(planned: [workout], activities: [run], calendar: calendar)
        XCTAssertEqual(matches[workout.id], run.id)
    }

    func testNoCrossDayMatching() {
        let workout = planned(day: 6, expectedMinutes: 50)
        let run = activity(day: 7, minutes: 50)
        let matches = WorkoutMatcher.matches(planned: [workout], activities: [run], calendar: calendar)
        XCTAssertTrue(matches.isEmpty)
    }

    func testActivityNotAssignedTwice() {
        let first = planned(day: 6, expectedMinutes: 50)
        let second = planned(day: 6, expectedMinutes: 52)
        let run = activity(day: 6, minutes: 51)
        let matches = WorkoutMatcher.matches(planned: [first, second], activities: [run], calendar: calendar)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(Set(matches.values), [run.id])
    }

    func testLoneRunRuleNeedsUnambiguousDay() {
        // Two unmatched workouts + one out-of-tolerance run → ambiguous, no match.
        let first = planned(day: 6, expectedMinutes: 50)
        let second = planned(day: 6, expectedMinutes: 250)
        let run = activity(day: 6, minutes: 125)
        let matches = WorkoutMatcher.matches(planned: [first, second], activities: [run], calendar: calendar)
        XCTAssertTrue(matches.isEmpty)
    }
}
