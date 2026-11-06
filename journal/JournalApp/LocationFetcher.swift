import CoreLocation

enum LocationError: LocalizedError {
    case denied
    var errorDescription: String? { "没有定位权限，请在「设置 → 隐私与安全性 → 定位服务」中允许“片刻”。" }
}

@MainActor
final class LocationFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetch() async throws -> Attachment {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { c in
                authContinuation = c
                manager.requestWhenInUseAuthorization()
            }
        }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { throw LocationError.denied }

        let location = try await withCheckedThrowingContinuation { (c: CheckedContinuation<CLLocation, Error>) in
            locationContinuation?.resume(throwing: CancellationError())
            locationContinuation = c
            manager.requestLocation()
        }

        let mark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Fmt.locale).first
        let name = mark?.name ?? mark?.subLocality ?? mark?.locality
            ?? String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        let detail = [mark?.locality, mark?.subLocality].compactMap { $0 }.filter { $0 != name }.first
        return Attachment(kind: .location,
                          placeName: detail.map { "\(name) · \($0)" } ?? name,
                          latitude: location.coordinate.latitude,
                          longitude: location.coordinate.longitude)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            self.authContinuation?.resume()
            self.authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: loc)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: error)
            self.locationContinuation = nil
        }
    }
}
