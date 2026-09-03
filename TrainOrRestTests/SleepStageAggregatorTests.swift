import XCTest
@testable import TrainOrRest

final class SleepStageAggregatorTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        DateComponents(calendar: calendar, year: 2026, month: 7, day: day, hour: hour, minute: minute).date!
    }

    private func interval(_ start: Date, _ end: Date, _ stage: SleepStage, source: String = "Garmin Connect") -> SleepInterval {
        SleepInterval(start: start, end: end, sourceName: source, stage: stage)
    }

    func testStagesSummedPerNightByWakeDate() {
        // 23:00–01:00 deep (2h), 01:00–05:00 light (4h), 05:00–06:00 REM (1h)
        let hours = SleepStageAggregator.nightlyStageHours(
            intervals: [
                interval(date(1, 23), date(2, 1), .deep),
                interval(date(2, 1), date(2, 5), .light),
                interval(date(2, 5), date(2, 6), .rem),
            ],
            calendar: calendar
        )
        let night = hours[calendar.startOfDay(for: date(2, 6))]!
        XCTAssertEqual(night.deep, 2, accuracy: 0.001)
        XCTAssertEqual(night.light, 4, accuracy: 0.001)
        XCTAssertEqual(night.rem, 1, accuracy: 0.001)
    }

    func testUnspecifiedCountsAsLight() {
        let hours = SleepStageAggregator.nightlyStageHours(
            intervals: [interval(date(1, 23), date(2, 6), .unspecified)],
            calendar: calendar
        )
        let night = hours[calendar.startOfDay(for: date(2, 6))]!
        XCTAssertEqual(night.light, 7, accuracy: 0.001)
        XCTAssertEqual(night.deep, 0)
        XCTAssertEqual(night.rem, 0)
    }

    func testStageHoursUseSourceWithMostStagedTimeForNight() {
        let hours = SleepStageAggregator.nightlyStageHours(
            intervals: [
                interval(date(1, 23), date(2, 1), .deep),
                interval(date(1, 22), date(2, 7), .unspecified, source: "iPhone"),
            ],
            calendar: calendar
        )
        let night = hours[calendar.startOfDay(for: date(2, 6))]!
        XCTAssertEqual(night.deep, 0, accuracy: 0.001)
        XCTAssertEqual(night.light, 9, accuracy: 0.001)
        XCTAssertEqual(night.rem, 0, accuracy: 0.001)
    }

    func testStageSourceTieBreakIsDeterministic() {
        let hours = SleepStageAggregator.nightlyStageHours(
            intervals: [
                interval(date(1, 23), date(2, 1), .deep, source: "Garmin Connect"),
                interval(date(1, 23), date(2, 1), .rem, source: "Apple Watch"),
            ],
            calendar: calendar
        )
        let night = hours[calendar.startOfDay(for: date(2, 1))]!
        XCTAssertEqual(night.deep, 0, accuracy: 0.001)
        XCTAssertEqual(night.rem, 2, accuracy: 0.001)
    }

    func testEmptyProducesNothing() {
        XCTAssertTrue(SleepStageAggregator.nightlyStageHours(intervals: [], calendar: calendar).isEmpty)
    }
}
