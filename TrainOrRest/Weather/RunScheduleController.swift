import CoreLocation
import Foundation

@MainActor
final class RunScheduleController: ObservableObject {
    static let weatherOverlayKey = "calendarShowsWeather"
    static let rainToleranceKey = "runScheduleRainTolerance"
    static let locationKey = "runScheduleLocation"
    static let setupCompletedKey = "runScheduleSetupCompleted"

    @Published var showsWeatherOverlay: Bool {
        didSet { UserDefaults.standard.set(showsWeatherOverlay, forKey: Self.weatherOverlayKey) }
    }
    @Published var rainTolerance: RainTolerance {
        didSet { UserDefaults.standard.set(rainTolerance.rawValue, forKey: Self.rainToleranceKey) }
    }
    @Published var location: RunLocation? {
        didSet { persistLocation() }
    }
    @Published private(set) var hourly: [HourlyWeatherSample] = []
    @Published private(set) var isRefreshingWeather = false
    @Published var weatherMessage: String?

    let locations: RunLocationProvider
    private let forecast: any WeatherForecasting
    private var lastFetchKey: String?

    init(forecast: any WeatherForecasting = WeatherKitForecastService()) {
        self.locations = RunLocationProvider()
        self.forecast = forecast
        showsWeatherOverlay = UserDefaults.standard.bool(forKey: Self.weatherOverlayKey)
        rainTolerance = RainTolerance(rawValue: UserDefaults.standard.string(forKey: Self.rainToleranceKey) ?? "") ?? .medium
        if let data = UserDefaults.standard.data(forKey: Self.locationKey),
           let saved = try? JSONDecoder().decode(RunLocation.self, from: data) {
            location = saved
        } else {
            location = nil
        }
    }

    var setupCompleted: Bool {
        UserDefaults.standard.bool(forKey: Self.setupCompletedKey) && location != nil
    }

    func markSetupCompleted() {
        UserDefaults.standard.set(true, forKey: Self.setupCompletedKey)
        if !showsWeatherOverlay {
            showsWeatherOverlay = true
        }
        objectWillChange.send()
    }

    func needsSetup(smartSchedulingEnabled: Bool) -> Bool {
        !setupCompleted || !smartSchedulingEnabled
    }

    func captureCurrentLocation() async {
        do {
            let current = try await locations.currentLocation()
            location = RunLocation(
                kind: .current,
                name: "Current location",
                latitude: current.coordinate.latitude,
                longitude: current.coordinate.longitude
            )
            await refreshWeather(force: true)
        } catch {
            weatherMessage = error.localizedDescription
        }
    }

    func searchPlace(_ query: String) async {
        do {
            location = try await locations.place(named: query)
            await refreshWeather(force: true)
        } catch {
            weatherMessage = error.localizedDescription
        }
    }

    func refreshWeather(force: Bool = false) async {
        guard showsWeatherOverlay || force else { return }
        guard let location else { return }
        let key = "\(location.latitude),\(location.longitude),\(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)"
        if !force, lastFetchKey == key { return }
        isRefreshingWeather = true
        defer { isRefreshingWeather = false }
        do {
            hourly = try await forecast.forecast(
                at: location.latitude,
                longitude: location.longitude,
                from: Date(),
                days: RunScheduleWeather.forecastHorizonDays
            )
            lastFetchKey = key
            weatherMessage = nil
        } catch {
            weatherMessage = error.localizedDescription
        }
    }

    func rank(_ candidates: [SchedulingCandidate]) -> [WeatherScoredCandidate] {
        RunScheduleWeather.rank(candidates, hourly: hourly, rainTolerance: rainTolerance)
    }

    func glyph(on day: Date) -> WeatherGlyph {
        RunScheduleWeather.dayGlyph(hourly: hourly, on: day, rainTolerance: rainTolerance)
    }

    func slotWeather(start: Date, end: Date) -> SlotWeather? {
        RunScheduleWeather.slotWeather(hourly: hourly, start: start, end: end, rainTolerance: rainTolerance)
    }

    private func persistLocation() {
        if let location, let data = try? JSONEncoder().encode(location) {
            UserDefaults.standard.set(data, forKey: Self.locationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.locationKey)
        }
    }
}
