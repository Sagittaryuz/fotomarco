import CoreLocation
import Foundation

@MainActor
protocol PreviewGeocoding: AnyObject {
    func resolve(_ location: CLLocation, completion: @escaping (String?) -> Void)
    func cancel()
}

@MainActor
private final class ApplePreviewGeocoder: PreviewGeocoding {
    private let geocoder = CLGeocoder()
    func resolve(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "pt_BR")) { placemarks, _ in
            let result = placemarks?.first.flatMap { StampAddress.format($0) }
            Task { @MainActor in completion(result) }
        }
    }
    func cancel() { geocoder.cancelGeocode() }
}

@MainActor
final class AddressPreviewService: ObservableObject {
    @Published private(set) var address: String?
    private var addressLocation: CLLocation?
    private var addressTime: Date?
    private var lastAttempt: Date?
    private var geocoder: PreviewGeocoding?
    private var generation = 0
    private let makeGeocoder: () -> PreviewGeocoding
    private let clock: () -> Date

    init() {
        self.makeGeocoder = { ApplePreviewGeocoder() }
        self.clock = Date.init
    }

    init(makeGeocoder: @escaping () -> PreviewGeocoding, clock: @escaping () -> Date) {
        self.makeGeocoder = makeGeocoder
        self.clock = clock
    }

    func update(location: CLLocation?, enabled: Bool, now: Date = Date()) {
        guard enabled, let location, Self.valid(location, at: now) else { clear(); return }
        if current(for: location, at: now) != nil { return }
        address = nil
        guard geocoder == nil, Self.mayRequest(lastAttempt: lastAttempt, now: now) else { return }
        lastAttempt = now
        generation += 1
        let requestGeneration = generation
        let request = makeGeocoder()
        geocoder = request
        request.resolve(location) { [weak self] formatted in
            guard let self, self.generation == requestGeneration else { return }
            self.geocoder = nil
            guard let formatted else { return }
            self.address = formatted
            self.addressLocation = location
            self.addressTime = self.clock()
        }
    }

    func current(for location: CLLocation?, at now: Date = Date()) -> String? {
        guard let location, Self.valid(location, at: now), let source = addressLocation, let time = addressTime,
              now >= time, now.timeIntervalSince(time) <= 60, location.distance(from: source) <= 20 else { return nil }
        return address
    }

    func clear() {
        generation += 1
        geocoder?.cancel()
        geocoder = nil
        address = nil
        addressLocation = nil
        addressTime = nil
    }

    static func mayRequest(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now < lastAttempt || now.timeIntervalSince(lastAttempt) >= 15
    }

    private static func valid(_ location: CLLocation, at now: Date) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate) && location.horizontalAccuracy >= 0 &&
            location.timestamp <= now && now.timeIntervalSince(location.timestamp) <= 60
    }
}
