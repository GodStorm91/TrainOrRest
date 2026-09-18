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

    func testSlotWeatherSummaryLeadsWithStanceAndNumbers() {
        let weather = SlotWeather(
            samples: [],
            temperatureRangeC: 18...22,
            precipitationMax: 0.10,
            windMaxKmh: 12,
            glyph: .good
        )
        XCTAssertEqual(
            PlanCopy(language: .en).slotWeatherSummary(weather),
            "Clear to run · 18–22°C · 10% rain · 12 km/h"
        )
        XCTAssertEqual(
            weather.summary(language: .en),
            "Clear to run · 18–22°C · 10% rain · 12 km/h"
        )
        XCTAssertTrue(PlanCopy(language: .ja).slotWeatherSummary(weather).hasPrefix("走れる天気"))
        XCTAssertTrue(PlanCopy(language: .vi).slotWeatherSummary(weather).hasPrefix("Trời ổn để chạy"))
    }

    func testAppleWeatherAttributionShowsTrademarkAndLegalSource() {
        XCTAssertEqual(
            WeatherDataAttribution.legalPageURL.absoluteString,
            "https://developer.apple.com/weatherkit/data-source-attribution/"
        )
        for language in CoachLanguage.allCases {
            let copy = PlanCopy(language: language)
            XCTAssertEqual(copy.appleWeatherMark, " Weather")
            XCTAssertFalse(copy.weatherLegalSource.isEmpty)
            XCTAssertTrue(copy.weatherAttributionAccessibility.contains(" Weather"))
            XCTAssertTrue(copy.weatherAttributionAccessibility.contains(copy.weatherLegalSource))
        }
        XCTAssertEqual(PlanCopy(language: .en).weatherLegalSource, "Other data sources")
        XCTAssertEqual(PlanCopy(language: .ja).weatherLegalSource, "その他のデータソース")
        XCTAssertEqual(PlanCopy(language: .vi).weatherLegalSource, "Nguồn dữ liệu khác")
    }

    func testRainToleranceCopyStatesTheCutoff() {
        let copy = PlanCopy(language: .en)
        XCTAssertEqual(copy.rainStanceLabel(.low), "Avoid rain")
        XCTAssertEqual(copy.rainToleranceCaption(.low), "Skip slots above 15% chance of rain.")
        XCTAssertEqual(copy.rainToleranceCaption(.medium), "Skip slots above 40% chance of rain.")
        XCTAssertEqual(copy.rainToleranceCaption(.high), "Skip slots above 70% chance of rain.")
    }

    func testDayAccessibilityIncludesWeatherStance() {
        let day = date(2026, 9, 5)
        let copy = PlanCopy(language: .en)
        let label = copy.dayAccessibility(
            date: day,
            kind: .easy,
            isToday: true,
            weatherStance: copy.weatherStance(.rainRisk)
        )
        XCTAssertTrue(label.contains("today"), label)
        XCTAssertTrue(label.contains("Rain risk"), label)
    }

    func testOpenMeteoMapsPercentRainAndFiltersHours() async throws {
        let http = StubWeatherHTTP(
            status: 200,
            body: openMeteoBody(times: ["2026-09-04T12:00", "2026-09-04T13:00", "2026-09-05T13:00"], rain: [40, 10, 90])
        )
        let samples = try await OpenMeteoForecastService(session: http).forecast(
            at: 21.0285,
            longitude: 105.8542,
            from: utc(2026, 9, 4, hour: 13),
            days: 1
        )
        XCTAssertEqual(http.lastURL?.host, "api.open-meteo.com")
        XCTAssertTrue(http.lastURL?.absoluteString.contains("forecast_days=1") == true)
        XCTAssertEqual(samples.map(\.precipitationChance), [0.1])
        XCTAssertEqual(samples.map(\.temperatureC), [21])
    }

    func testOpenMeteoThrowsUnavailableOnHTTPError() async {
        let http = StubWeatherHTTP(status: 500, body: Data("{}".utf8))
        do {
            _ = try await OpenMeteoForecastService(session: http).forecast(
                at: 21,
                longitude: 105,
                from: utc(2026, 9, 4, hour: 0),
                days: 10
            )
            XCTFail("expected unavailable")
        } catch let error as WeatherForecastingError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testFallbackUsesOpenMeteoWhenWeatherKitThrows() async throws {
        let http = StubWeatherHTTP(
            status: 200,
            body: openMeteoBody(times: ["2026-09-04T13:00"], rain: [25])
        )
        let service = FallbackWeatherForecastService(
            primary: StubForecastService(result: .failure(WeatherForecastingError.unavailable)),
            fallback: OpenMeteoForecastService(session: http)
        )
        let samples = try await service.forecast(
            at: 21,
            longitude: 105,
            from: utc(2026, 9, 4, hour: 13),
            days: 1
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].precipitationChance, 0.25, accuracy: 0.0001)
    }

    func testFallbackUsesOpenMeteoWhenWeatherKitJWTFails() async throws {
        let jwt = NSError(
            domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Error",
            code: 2
        )
        let http = StubWeatherHTTP(
            status: 200,
            body: openMeteoBody(times: ["2026-09-04T13:00"], rain: [25])
        )
        let service = FallbackWeatherForecastService(
            primary: StubForecastService(result: .failure(jwt)),
            fallback: OpenMeteoForecastService(session: http)
        )
        let samples = try await service.forecast(
            at: 21,
            longitude: 105,
            from: utc(2026, 9, 4, hour: 13),
            days: 1
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].precipitationChance, 0.25, accuracy: 0.0001)
    }

    func testFallbackUsesOpenMeteoWhenWeatherKitReturnsEmpty() async throws {
        let http = StubWeatherHTTP(
            status: 200,
            body: openMeteoBody(times: ["2026-09-04T13:00"], rain: [0])
        )
        let service = FallbackWeatherForecastService(
            primary: StubForecastService(result: .success([])),
            fallback: OpenMeteoForecastService(session: http)
        )
        let samples = try await service.forecast(
            at: 21,
            longitude: 105,
            from: utc(2026, 9, 4, hour: 13),
            days: 1
        )
        XCTAssertEqual(samples.count, 1)
    }

    @MainActor
    func testRefreshWeatherClearsUnavailableAfterSuccessfulFetch() async {
        let samples = [sample(date(2026, 9, 5, hour: 8), rain: 0.1, wind: 5)]
        let controller = RunScheduleController(forecast: StubForecastService(result: .success(samples)))
        controller.location = RunLocation(kind: .city, name: "Hanoi", latitude: 21.0285, longitude: 105.8542)
        await controller.refreshWeather(force: true)
        XCTAssertNil(controller.weatherUserMessage)
        XCTAssertEqual(controller.hourly, samples)
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

    private func utc(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func openMeteoBody(times: [String], rain: [Double]) -> Data {
        let temps = Array(repeating: 21.0, count: times.count)
        let winds = Array(repeating: 8.0, count: times.count)
        let payload: [String: Any] = [
            "hourly": [
                "time": times,
                "temperature_2m": temps,
                "precipitation_probability": rain,
                "wind_speed_10m": winds,
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}

private final class StubWeatherHTTP: WeatherHTTPSessioning, @unchecked Sendable {
    var status: Int
    var body: Data
    var lastURL: URL?

    init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        lastURL = url
        return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private struct StubForecastService: WeatherForecasting {
    var result: Result<[HourlyWeatherSample], Error>

    func forecast(
        at latitude: Double,
        longitude: Double,
        from start: Date,
        days: Int
    ) async throws -> [HourlyWeatherSample] {
        try result.get()
    }
}
