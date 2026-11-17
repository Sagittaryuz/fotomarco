import CoreLocation
import Foundation
import Observation

/// The locked experience never asks for a new permission. It only uses a fresh
/// location if iOS grants the existing permission to this extension.
@Observable @MainActor
final class LockedLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var location: CLLocation?
    private(set) var heading: CLHeading?
    private var enabled = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func startIfAuthorized(_ enabled: Bool) {
        self.enabled = enabled
        refreshAuthorization()
    }

    func stop() {
        enabled = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        location = nil
        heading = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refreshAuthorization() }

    private func refreshAuthorization() {
        guard enabled, manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
            location = nil
            heading = nil
            return
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0,
              abs(value.timestamp.timeIntervalSinceNow) <= 60 else { return }
        location = value
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading value: CLHeading) {
        guard value.headingAccuracy >= 0 else { return }
        heading = value
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        location = nil
        heading = nil
    }
}
