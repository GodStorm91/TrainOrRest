import XCTest
@testable import TrainOrRest

final class RunScheduleTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    func testRainOverToleranceRejectsWholeSlot() {
        let start = date(2026, 9, 5, hour: 6)
        let end = date(2026, 9, 5, hour: 8)
        let candidate = makeCandidate(start: start, end: end, score: 130)
        let hourly = [
            sample(date(2026, 9, 5, hour: 6), rain: 0.05, wind: 8),
            sample(date(2026, 9, 5, hour: 7), rain: 0.55, wind: 10)
        ]

        let ranked = RunScheduleWeather.rank(
            [candidate],
            hourly: hourly,
            rainTolerance: .low,
            now: date(2026, 9, 4, hour: 12)
        )

        XCTAssertTrue(ranked.isEmpty)
    }

    func testDryEveningOutranksRainyMorningEvenWithLowerEngineScore() {
        let morning = makeCandidate(start: date(2026, 9, 5, hour: 6), end: date(2026, 9, 5, hour: 8), score: 140)
        let evening = makeCandidate(start: date(2026, 9, 5, hour: 18), end: date(2026, 9, 5, hour: 20), score: 110)
        let hourly = [
            sample(date(2026, 9, 5, hour: 6), rain: 0.30, wind: 12),
            sample(date(2026, 9, 5, hour: 7), rain: 0.32, wind: 14),
            sample(date(2026, 9, 5, hour: 18), rain: 0.05, wind: 8),
            sample(date(2026, 9, 5, hour: 19), rain: 0.04, wind: 7)
        ]

        let ranked = RunScheduleWeather.rank(
            [morning, evening],
            hourly: hourly,
            rainTolerance: .medium,
            now: date(2026, 9, 4, hour: 12)
        )

        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(calendar.component(.hour, from: ranked[0].candidate.startTime), 18)
        XCTAssertEqual(ranked[0].weather?.glyph, .good)
        XCTAssertEqual(ranked[1].weather?.glyph, .rainRisk)
    }

    func testDaysBeyondForecastHorizonHaveNoDataGlyph() {
        let glyph = RunScheduleWeather.dayGlyph(
            hourly: [sample(date(2026, 9, 5, hour: 8), rain: 0.1, wind: 5)],
            on: date(2026, 9, 20),
            calendar: calendar,
            rainTolerance: .medium,
            now: date(2026, 9, 4, hour: 8)
        )
        XCTAssertEqual(glyph, .noData)
    }

    func testMidnightDateIsUnscheduledAndHourIsBooked() {
        XCTAssertFalse(RunScheduleTime.isTimed(calendar.startOfDay(for: date(2026, 9, 5)), calendar: calendar))
        XCTAssertTrue(RunScheduleTime.isTimed(date(2026, 9, 5, hour: 6), calendar: calendar))
    }

    private func makeCandidate(start: Date, end: Date, score: Int) -> SchedulingCandidate {
        SchedulingCandidate(
            workoutID: UUID(),
            workoutVersion: "test",
            date: calendar.startOfDay(for: start),
            startTime: start,
            endTime: end,
            timezone: calendar.timeZone,
            score: score,
            isRecommended: false,
            validationStatus: .valid,
            reasons: ["No calendar conflicts"],
            warnings: [],
            conflicts: [],
            availabilitySourceTimestamp: nil
        )
    }

    private func sample(_ date: Date, rain: Double, wind: Double) -> HourlyWeatherSample {
        HourlyWeatherSample(hourStart: date, temperatureC: 21, precipitationChance: rain, windKmh: wind)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }
}
