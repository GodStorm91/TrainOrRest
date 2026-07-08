import XCTest
@testable import TrainOrRest

final class TrainingStreakTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 8)

    private func daysAgo(_ ns: [Int]) -> [Date] {
        ns.map { calendar.date(byAdding: .day, value: -$0, to: today)! }
    }

    func testEmptyHistoryIsZero() {
        XCTAssertEqual(TrainingStreak.current(activityDates: [], today: today, calendar: calendar), 0)
    }

    func testConsecutiveDaysEndingToday() {
        XCTAssertEqual(TrainingStreak.current(activityDates: daysAgo([0, 1, 2, 3]), today: today, calendar: calendar), 4)
    }

    func testRestTodayKeepsStreakAliveFromYesterday() {
        // No run today, but a run yesterday and before → streak counts through yesterday.
        XCTAssertEqual(TrainingStreak.current(activityDates: daysAgo([1, 2, 3]), today: today, calendar: calendar), 3)
    }

    func testGapBreaksStreak() {
        // Runs at 0 and 1, then a gap at 2 → streak is 2.
        XCTAssertEqual(TrainingStreak.current(activityDates: daysAgo([0, 1, 3, 4]), today: today, calendar: calendar), 2)
    }

    func testStaleHistoryIsZero() {
        // Last run was 2 days ago (neither today nor yesterday) → broken.
        XCTAssertEqual(TrainingStreak.current(activityDates: daysAgo([2, 3, 4]), today: today, calendar: calendar), 0)
    }

    func testMultipleRunsSameDayCountOnce() {
        let twoToday = [today, calendar.date(byAdding: .hour, value: -3, to: today)!]
        XCTAssertEqual(TrainingStreak.current(activityDates: twoToday, today: today, calendar: calendar), 1)
    }
}
