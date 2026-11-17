import CoreLocation
import Foundation

@MainActor
final class AddressPreviewService: ObservableObject {
    @Published private(set) var address: String?
    private var addressLocation: CLLocation?
    private var addressTime: Date?
    private var lastAttempt: Date?
    private var geocoder: CLGeocoder?
    private var generation = 0

    func update(location: CLLocation?, enabled: Bool, now: Date = Date()) {
        guard enabled, let location, Self.valid(location, at: now) else { clear(); return }
        if current(for: location, at: now) != nil { return }
        address = nil
        guard geocoder == nil, Self.mayRequest(lastAttempt: lastAttempt, now: now) else { return }
        lastAttempt = now
        generation += 1
        let requestGeneration = generation
        let request = CLGeocoder()
        geocoder = request
        request.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "pt_BR")) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self, self.generation == requestGeneration else { return }
                self.geocoder = nil
                guard let placemark = placemarks?.first, let formatted = StampAddress.format(placemark) else { return }
                self.address = formatted
                self.addressLocation = location
                self.addressTime = Date()
            }
        }
    }

    func current(for location: CLLocation?, at now: Date = Date()) -> String? {
        guard let location, Self.valid(location, at: now), let source = addressLocation, let time = addressTime,
              now >= time, now.timeIntervalSince(time) <= 60, location.distance(from: source) <= 20 else { return nil }
        return address
    }

    func clear() {
        generation += 1
        geocoder?.cancelGeocode()
        geocoder = nil
        address = nil
        addressLocation = nil
        addressTime = nil
    }

    static func mayRequest(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now < lastAttempt || now.timeIntervalSince(lastAttempt) >= 60
    }

    private static func valid(_ location: CLLocation, at now: Date) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate) && location.horizontalAccuracy >= 0 &&
            location.timestamp <= now && now.timeIntervalSince(location.timestamp) <= 60
    }
}
