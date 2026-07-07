import XCTest
@testable import TrainOrRest

final class SampleMappingTests: XCTestCase {
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

    // MARK: - Pace

    func testPaceComputedFromDistanceAndDuration() {
        let pace = ActivityMapper.averagePaceSecondsPerKm(distanceMeters: 10_000, durationSeconds: 3_000)
        XCTAssertEqual(pace, 300)
    }

    func testPaceNilWhenDistanceMissingOrZero() {
        XCTAssertNil(ActivityMapper.averagePaceSecondsPerKm(distanceMeters: nil, durationSeconds: 3_000))
        XCTAssertNil(ActivityMapper.averagePaceSecondsPerKm(distanceMeters: 0, durationSeconds: 3_000))
        XCTAssertNil(ActivityMapper.averagePaceSecondsPerKm(distanceMeters: 10_000, durationSeconds: 0))
    }

    // MARK: - Garmin source preference

    func testPreferGarminDropsOtherSourcesWhenGarminPresent() {
        let samples = [
            QuantitySampleSummary(start: date(1, 6), value: 50, sourceName: "Garmin Connect"),
            QuantitySampleSummary(start: date(1, 7), value: 60, sourceName: "iPhone"),
        ]
        let kept = GarminSource.preferGarmin(samples, sourceName: \.sourceName)
        XCTAssertEqual(kept.map(\.value), [50])
    }

    func testPreferGarminKeepsAllWhenGarminAbsent() {
        let samples = [
            QuantitySampleSummary(start: date(1, 6), value: 50, sourceName: "iPhone"),
            QuantitySampleSummary(start: date(1, 7), value: 60, sourceName: "Apple Watch"),
        ]
        let kept = GarminSource.preferGarmin(samples, sourceName: \.sourceName)
        XCTAssertEqual(kept.count, 2)
    }

    // MARK: - Daily reducers

    func testFirstValuePerDayPicksEarliestSample() {
        let samples = [
            QuantitySampleSummary(start: date(1, 9), value: 45, sourceName: "Garmin Connect"),
            QuantitySampleSummary(start: date(1, 4), value: 52, sourceName: "Garmin Connect"),
            QuantitySampleSummary(start: date(2, 5), value: 48, sourceName: "Garmin Connect"),
        ]
        let byDay = WellnessReducer.firstValuePerDay(samples, calendar: calendar)
        XCTAssertEqual(byDay[calendar.startOfDay(for: date(1, 4))], 52)
        XCTAssertEqual(byDay[calendar.startOfDay(for: date(2, 5))], 48)
        XCTAssertEqual(byDay.count, 2)
    }

    func testLatestValuePerDayPicksMostRecentSample() {
        let samples = [
            QuantitySampleSummary(start: date(1, 8), value: 55, sourceName: "Garmin Connect"),
            QuantitySampleSummary(start: date(1, 21), value: 53, sourceName: "Garmin Connect"),
        ]
        let byDay = WellnessReducer.latestValuePerDay(samples, calendar: calendar)
        XCTAssertEqual(byDay[calendar.startOfDay(for: date(1, 8))], 53)
    }

    func testReducersEmptyInputProducesEmptyOutput() {
        XCTAssertTrue(WellnessReducer.firstValuePerDay([], calendar: calendar).isEmpty)
        XCTAssertTrue(WellnessReducer.latestValuePerDay([], calendar: calendar).isEmpty)
    }
}
