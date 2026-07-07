import XCTest
@testable import TrainOrRest

final class PlanDiffTests: XCTestCase {
    private let calendar = PlanEngineTestSupport.calendar
    private let today = PlanEngineTestSupport.date(2026, 7, 8)

    private func entry(dayOffset: Int, kind: WorkoutKind, km: Double) -> PlanDiff.Entry {
        PlanDiff.Entry(
            date: calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: today))!,
            kind: kind,
            distanceKm: km,
            paceBand: nil
        )
    }

    func testIdenticalPlansProduceNoChanges() {
        let entries = [entry(dayOffset: 0, kind: .easy, km: 8), entry(dayOffset: 2, kind: .tempo, km: 10)]
        let changes = PlanDiff.changes(
            previous: entries, current: entries, today: today, todayVerdict: .train, calendar: calendar
        )
        XCTAssertTrue(changes.isEmpty)
    }

    func testTodayChangeAttributedToReadiness() {
        let previous = [entry(dayOffset: 0, kind: .intervals, km: 10)]
        let current = [entry(dayOffset: 0, kind: .easy, km: 10)]
        let changes = PlanDiff.changes(
            previous: previous, current: current, today: today, todayVerdict: .goEasy, calendar: calendar
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].reason, .readiness(.goEasy))
        XCTAssertEqual(changes[0].before?.kind, .intervals)
        XCTAssertEqual(changes[0].after?.kind, .easy)
    }

    func testLaterDistanceChangeIsVolumeRefit() {
        let previous = [entry(dayOffset: 3, kind: .easy, km: 8)]
        let current = [entry(dayOffset: 3, kind: .easy, km: 10)]
        let changes = PlanDiff.changes(
            previous: previous, current: current, today: today, todayVerdict: .goEasy, calendar: calendar
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].reason, .volumeRefit)
    }

    func testRemovedDayShowsAsRest() {
        let previous = [entry(dayOffset: 0, kind: .easy, km: 8)]
        let changes = PlanDiff.changes(
            previous: previous, current: [], today: today, todayVerdict: .rest, calendar: calendar
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertNil(changes[0].after)
        XCTAssertEqual(changes[0].reason, .readiness(.rest))
    }

    func testChangesBeyondWindowIgnored() {
        let previous = [entry(dayOffset: 20, kind: .easy, km: 8)]
        let current = [entry(dayOffset: 20, kind: .tempo, km: 12)]
        let changes = PlanDiff.changes(
            previous: previous, current: current, today: today, todayVerdict: .train, calendar: calendar
        )
        XCTAssertTrue(changes.isEmpty)
    }

    func testTinyDistanceRoundingIsNotAChange() {
        let previous = [entry(dayOffset: 1, kind: .easy, km: 8.0)]
        let current = [entry(dayOffset: 1, kind: .easy, km: 8.04)]
        let changes = PlanDiff.changes(
            previous: previous, current: current, today: today, todayVerdict: .train, calendar: calendar
        )
        XCTAssertTrue(changes.isEmpty)
    }
}
