#if DEBUG
import CoreLocation

@MainActor
final class LauncherWeatherLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<CLLocation, Error>?
    private var timeout: Task<Void, Never>?
    enum Failure: Error { case permission, unavailable }
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    var authorized: Bool { manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse }
    var denied: Bool { manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted }
    func current() async throws -> LauncherWeatherCity {
        guard pending == nil else { throw Failure.unavailable }
        let location: CLLocation = try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                self?.finish(.failure(Failure.unavailable))
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            default: finish(.failure(Failure.permission))
            }
        }
        try Task.checkCancellation()
        let places = try? await CLGeocoder().reverseGeocodeLocation(location)
        try Task.checkCancellation()
        let place = places?.first
        let name = [place?.locality ?? place?.subAdministrativeArea, place?.administrativeArea].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " · ")
        return LauncherWeatherCity(name: name.isEmpty ? "현재 위치" : name, latitude: (location.coordinate.latitude * 100).rounded() / 100, longitude: (location.coordinate.longitude * 100).rounded() / 100)
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<CLLocation, Error>) {
        timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation()
        let continuation = pending; pending = nil
        continuation?.resume(with: result)
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pending != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finish(.failure(Failure.permission))
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 600 }) else { finish(.failure(Failure.unavailable)); return }
        finish(.success(location))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(.failure(Failure.unavailable)) }
}
#endif
