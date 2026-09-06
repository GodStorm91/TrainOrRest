import Foundation
import OSLog

protocol WeatherHTTPSessioning: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: WeatherHTTPSessioning {}

/// Open-Meteo hourly forecast. Used when WeatherKit JWT auth fails.
struct OpenMeteoForecastService: WeatherForecasting {
    var session: any WeatherHTTPSessioning

    init(session: any WeatherHTTPSessioning = URLSession.shared) {
        self.session = session
    }
    func forecast(
        at latitude: Double,
        longitude: Double,
        from start: Date,
        days: Int
    ) async throws -> [HourlyWeatherSample] {
        let days = min(max(days, 1), RunScheduleWeather.forecastHorizonDays)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,wind_speed_10m"),
            URLQueryItem(name: "forecast_days", value: String(days)),
            URLQueryItem(name: "timezone", value: "GMT"),
        ]
        guard let url = components?.url else { throw WeatherForecastingError.unavailable }
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw WeatherForecastingError.unavailable }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let horizon = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let parser = Self.timeParser()
        var samples: [HourlyWeatherSample] = []
        samples.reserveCapacity(payload.hourly.time.count)
        for index in payload.hourly.time.indices {
            let stamp = payload.hourly.time[index]
            guard let hourStart = parser.date(from: stamp) else { continue }
            guard hourStart >= start && hourStart < horizon else { continue }
            let temperature = Self.number(payload.hourly.temperature_2m, index)
            let rainPercent = Self.number(payload.hourly.precipitation_probability, index)
            let wind = Self.number(payload.hourly.wind_speed_10m, index)
            samples.append(
                HourlyWeatherSample(
                    hourStart: hourStart,
                    temperatureC: temperature,
                    precipitationChance: min(max(rainPercent / 100, 0), 1),
                    windKmh: wind
                )
            )
        }
        return samples
    }
    private static func timeParser() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }

    private static func number(_ values: [Double?], _ index: Int) -> Double {
        guard values.indices.contains(index) else { return 0 }
        return values[index] ?? 0
    }

    private struct Payload: Decodable {
        var hourly: Hourly

        struct Hourly: Decodable {
            var time: [String]
            var temperature_2m: [Double?]
            var precipitation_probability: [Double?]
            var wind_speed_10m: [Double?]
        }
    }
}

struct FallbackWeatherForecastService: WeatherForecasting {
    var primary: any WeatherForecasting
    var fallback: any WeatherForecasting

    func forecast(
        at latitude: Double,
        longitude: Double,
        from start: Date,
        days: Int
    ) async throws -> [HourlyWeatherSample] {
        do {
            let samples = try await primary.forecast(
                at: latitude,
                longitude: longitude,
                from: start,
                days: days
            )
            if !samples.isEmpty { return samples }
            Self.log.error("primary forecast returned no hours; falling back to Open-Meteo")
        } catch {
            Self.log.error("primary forecast failed (\(error.localizedDescription, privacy: .public)); falling back to Open-Meteo")
        }
        return try await fallback.forecast(
            at: latitude,
            longitude: longitude,
            from: start,
            days: days
        )
    }

    private static let log = Logger(subsystem: "com.khanhnguyen.TrainOrRest", category: "weather")
}

