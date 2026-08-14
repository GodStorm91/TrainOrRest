import XCTest
@testable import TrainOrRest

final class SleepAggregationTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            year: 2026, month: 7, day: day, hour: hour, minute: minute
        ).date!
    }

    private func garmin(_ start: Date, _ end: Date) -> SleepInterval {
        SleepInterval(start: start, end: end, sourceName: "Garmin Connect")
    }

    func testNightCrossingMidnightAttributedToWakeDate() {
        // 23:00 → 06:30 = 7.5h, attributed to the morning's date
        let hours = SleepAggregator.nightlySleepHours(
            intervals: [garmin(date(1, 23), date(2, 6, 30))],
            calendar: calendar
        )
        XCTAssertEqual(hours[calendar.startOfDay(for: date(2, 6))]!, 7.5, accuracy: 0.001)
        XCTAssertEqual(hours.count, 1)
    }

    func testSleepStagesSummedWithoutGaps() {
        // Deep 23:00–01:00, core 01:00–05:00, REM 05:30–06:30 (awake gap 05:00–05:30)
        let hours = SleepAggregator.nightlySleepHours(
            intervals: [
                garmin(date(1, 23), date(2, 1)),
                garmin(date(2, 1), date(2, 5)),
                garmin(date(2, 5, 30), date(2, 6, 30)),
            ],
            calendar: calendar
        )
        XCTAssertEqual(hours[calendar.startOfDay(for: date(2, 6))]!, 7.0, accuracy: 0.001)
    }

    func testOverlappingIntervalsNotDoubleCounted() {
        // Duplicate/overlapping records covering 23:00–07:00 = 8h total
        let hours = SleepAggregator.nightlySleepHours(
            intervals: [
                garmin(date(1, 23), date(2, 6)),
                garmin(date(2, 4), date(2, 7)),
                garmin(date(1, 23), date(2, 6)),
            ],
            calendar: calendar
        )
        XCTAssertEqual(hours[calendar.startOfDay(for: date(2, 6))]!, 8.0, accuracy: 0.001)
    }

    func testTwoNightsProduceTwoEntries() {
        let hours = SleepAggregator.nightlySleepHours(
            intervals: [
                garmin(date(1, 23), date(2, 6)),
                garmin(date(2, 23), date(3, 7)),
            ],
            calendar: calendar
        )
        XCTAssertEqual(hours.count, 2)
        XCTAssertEqual(hours[calendar.startOfDay(for: date(2, 6))]!, 7.0, accuracy: 0.001)
        XCTAssertEqual(hours[calendar.startOfDay(for: date(3, 7))]!, 8.0, accuracy: 0.001)
    }

    func testSleepAggregatesAllSourcesWithOverlapMerge() {
        // HealthKit sleep aggregates all sources; overlapping windows merge,
        // so Garmin 23:00-06:00 plus iPhone 22:00-08:00 becomes 10h.
        let hours = SleepAggregator.nightlySleepHours(
            intervals: [
                garmin(date(1, 23), date(2, 6)),
                SleepInterval(start: date(1, 22), end: date(2, 8), sourceName: "iPhone"),
            ],
            calendar: calendar
        )
        XCTAssertEqual(hours[calendar.startOfDay(for: date(2, 6))]!, 10.0, accuracy: 0.001)
    }

    func testInvalidAndEmptyIntervalsIgnored() {
        XCTAssertTrue(SleepAggregator.nightlySleepHours(intervals: [], calendar: calendar).isEmpty)
        let hours = SleepAggregator.nightlySleepHours(
            intervals: [garmin(date(2, 6), date(2, 6))],
            calendar: calendar
        )
        XCTAssertTrue(hours.isEmpty)
    }
}
