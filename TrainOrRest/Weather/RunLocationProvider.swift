import CoreLocation
import Foundation

@MainActor
final class RunLocationProvider: NSObject, ObservableObject {
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func currentLocation() async throws -> CLLocation {
        if !isAuthorized {
            requestWhenInUse()
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func place(named query: String) async throws -> RunLocation {
        let geocoder = CLGeocoder()
        let marks = try await geocoder.geocodeAddressString(query)
        guard let mark = marks.first, let location = mark.location else {
            throw WeatherForecastingError.unavailable
        }
        let name = [mark.name, mark.locality, mark.administrativeArea]
            .compactMap { $0 }
            .uniqued()
            .joined(separator: ", ")
        return RunLocation(
            kind: .city,
            name: name.isEmpty ? query : name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}

extension RunLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorization = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
