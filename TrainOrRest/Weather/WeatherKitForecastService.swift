import CoreLocation
import Foundation
import WeatherKit

struct WeatherKitForecastService: WeatherForecasting {
    func forecast(at latitude: Double, longitude: Double, from start: Date, days: Int) async throws -> [HourlyWeatherSample] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let days = min(max(days, 1), RunScheduleWeather.forecastHorizonDays)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let hourly = try await WeatherService.shared.weather(
            for: location,
            including: .hourly(startDate: start, endDate: end)
        )
        return hourly.map { hour in
            HourlyWeatherSample(
                hourStart: hour.date,
                temperatureC: hour.temperature.converted(to: .celsius).value,
                precipitationChance: hour.precipitationChance,
                windKmh: hour.wind.speed.converted(to: .kilometersPerHour).value
            )
        }
    }
}
