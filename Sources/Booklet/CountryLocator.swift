import CoreLocation
import Foundation

@MainActor
final class CountryLocator: NSObject, CLLocationManagerDelegate {
    var onCountry: ((String?) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isLocating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func locate() {
        guard !isLocating else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            onCountry?(nil)
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            manager.requestLocation()
        case .denied, .restricted:
            onCountry?(nil)
        @unknown default:
            onCountry?(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.handleLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.handleLocationFailure()
        }
    }

    private func handleAuthorizationChange() {
        guard isLocating else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            onCountry?(nil)
        default:
            break
        }
    }

    private func handleLocation(_ location: CLLocation) {
        guard isLocating else { return }
        isLocating = false
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let countryCode = placemarks?.first?.isoCountryCode
            Task { @MainActor [weak self] in
                self?.onCountry?(countryCode)
            }
        }
    }

    private func handleLocationFailure() {
        isLocating = false
        onCountry?(nil)
    }
}
