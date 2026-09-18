import Foundation

enum RainTolerance: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    /// Maximum precipitation chance a slot may carry before it is rejected.
    var maxPrecipitationChance: Double {
        switch self {
        case .low: 0.15
        case .medium: 0.40
        case .high: 0.70
        }
    }
}

enum WeatherGlyph: String, Equatable {
    case good
    case rainRisk
    case strongWind
    case noSlot
    case noData

    var systemImage: String {
        switch self {
        case .good: "sun.max.fill"
        case .rainRisk: "cloud.rain.fill"
        case .strongWind: "wind"
        case .noSlot: "cloud.heavyrain.fill"
        case .noData: "questionmark.circle"
        }
    }
}

struct HourlyWeatherSample: Equatable, Sendable {
    var hourStart: Date
    var temperatureC: Double
    var precipitationChance: Double
    var windKmh: Double
}

struct SlotWeather: Equatable {
    var samples: [HourlyWeatherSample]
    var temperatureRangeC: ClosedRange<Double>
    var precipitationMax: Double
    var windMaxKmh: Double
    var glyph: WeatherGlyph

    func summary(language: CoachLanguage) -> String {
        language.plan.slotWeatherSummary(self)
    }
}

struct WeatherScoredCandidate: Identifiable, Equatable {
    var candidate: SchedulingCandidate
    var weather: SlotWeather?
    var adjustedScore: Int

    var id: String { candidate.id }
    var isValid: Bool { candidate.isValid && weather?.glyph != .noSlot }
}

enum RunScheduleBooking: Equatable {
    case unscheduled
    case scheduled(start: Date, end: Date)
    case conflicted(start: Date, end: Date)
}

struct RunLocation: Equatable, Codable, Sendable {
    enum Kind: String, Codable {
        case current
        case saved
        case map
        case city
    }

    var kind: Kind
    var name: String
    var latitude: Double
    var longitude: Double
}

enum WeatherForecastingError: Error, Equatable {
    case missingLocation
    case unavailable
}

enum WeatherDataAttribution {
    static let legalPageURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!
}

protocol WeatherForecasting: Sendable {
    func forecast(at latitude: Double, longitude: Double, from start: Date, days: Int) async throws -> [HourlyWeatherSample]
}

enum RunScheduleWeather {
    static let strongWindKmh = 24.0
    static let rejectWindKmh = 40.0
    static let forecastHorizonDays = 10

    static func samples(
        _ hourly: [HourlyWeatherSample],
        overlapping start: Date,
        end: Date
    ) -> [HourlyWeatherSample] {
        hourly.filter { sample in
            let sampleEnd = sample.hourStart.addingTimeInterval(3600)
            return sample.hourStart < end && sampleEnd > start
        }
        .sorted { $0.hourStart < $1.hourStart }
    }

    static func slotWeather(
        hourly: [HourlyWeatherSample],
        start: Date,
        end: Date,
        rainTolerance: RainTolerance,
        now: Date = .now
    ) -> SlotWeather? {
        let horizon = Calendar.current.date(byAdding: .day, value: forecastHorizonDays, to: Calendar.current.startOfDay(for: now)) ?? now
        guard start < horizon else { return nil }
        let overlapping = samples(hourly, overlapping: start, end: end)
        guard !overlapping.isEmpty else {
            return nil
        }
        let temps = overlapping.map(\.temperatureC)
        let precip = overlapping.map(\.precipitationChance).max() ?? 0
        let wind = overlapping.map(\.windKmh).max() ?? 0
        let low = temps.min() ?? 0
        let high = temps.max() ?? 0
        let glyph: WeatherGlyph
        if precip > rainTolerance.maxPrecipitationChance || wind > rejectWindKmh {
            glyph = .noSlot
        } else if precip > rainTolerance.maxPrecipitationChance * 0.6 {
            glyph = .rainRisk
        } else if wind >= strongWindKmh {
            glyph = .strongWind
        } else {
            glyph = .good
        }
        return SlotWeather(
            samples: overlapping,
            temperatureRangeC: low...high,
            precipitationMax: precip,
            windMaxKmh: wind,
            glyph: glyph
        )
    }

    static func dayGlyph(
        hourly: [HourlyWeatherSample],
        on day: Date,
        calendar: Calendar = .current,
        rainTolerance: RainTolerance,
        now: Date = .now
    ) -> WeatherGlyph {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return .noData }
        let horizon = calendar.date(byAdding: .day, value: forecastHorizonDays, to: calendar.startOfDay(for: now)) ?? now
        guard start < horizon else { return .noData }
        guard let weather = slotWeather(hourly: hourly, start: start, end: end, rainTolerance: rainTolerance, now: now) else {
            return .noData
        }
        return weather.glyph
    }

    /// Reranks calendar-valid candidates with weather over the whole slot, not the start hour.
    static func rank(
        _ candidates: [SchedulingCandidate],
        hourly: [HourlyWeatherSample],
        rainTolerance: RainTolerance,
        now: Date = .now
    ) -> [WeatherScoredCandidate] {
        let scored = candidates.map { candidate -> WeatherScoredCandidate in
            let weather = slotWeather(
                hourly: hourly,
                start: candidate.startTime,
                end: candidate.endTime,
                rainTolerance: rainTolerance,
                now: now
            )
            var adjusted = candidate.score
            switch weather?.glyph {
            case .good:
                adjusted += 20
            case .rainRisk:
                adjusted -= 12
            case .strongWind:
                adjusted -= 8
            case .noSlot:
                adjusted = 0
            case .noData, .none:
                break
            }
            return WeatherScoredCandidate(candidate: candidate, weather: weather, adjustedScore: adjusted)
        }
        return scored
            .filter(\.isValid)
            .sorted { lhs, rhs in
                if lhs.adjustedScore != rhs.adjustedScore { return lhs.adjustedScore > rhs.adjustedScore }
                return lhs.candidate.startTime < rhs.candidate.startTime
            }
    }
}

enum RunScheduleTime {
    static func isTimed(_ date: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
    }
}

extension PlannedWorkout {
    var hasScheduledStartTime: Bool { RunScheduleTime.isTimed(date) }
}
