import CoreLocation
import Foundation
import WeatherKit

struct WeatherKitForecastService: WeatherForecasting {
    func forecast(at latitude: Double, longitude: Double, from start: Date, days: Int) async throws -> [HourlyWeatherSample] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let hourly = try await WeatherService.shared.weather(for: location, including: .hourly)
        let horizon = Calendar.current.date(byAdding: .day, value: min(days, RunScheduleWeather.forecastHorizonDays), to: start) ?? start
        return hourly.compactMap { hour in
            guard hour.date >= start && hour.date < horizon else { return nil }
            return HourlyWeatherSample(
                hourStart: hour.date,
                temperatureC: hour.temperature.converted(to: .celsius).value,
                precipitationChance: hour.precipitationChance,
                windKmh: hour.wind.speed.converted(to: .kilometersPerHour).value
            )
        }
    }
}
