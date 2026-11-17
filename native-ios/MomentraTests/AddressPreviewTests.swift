import XCTest
import CoreLocation
@testable import Momentra

@MainActor
private final class FakePreviewGeocoder: PreviewGeocoding {
    var completion: ((String?) -> Void)?
    var cancelled = false
    func resolve(_ location: CLLocation, completion: @escaping (String?) -> Void) { self.completion = completion }
    func cancel() { cancelled = true }
}

@MainActor
final class AddressPreviewTests: XCTestCase {
    private func fix(_ latitude: Double, time: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -51.7), altitude: 700,
            horizontalAccuracy: 8, verticalAccuracy: 5, timestamp: time)
    }

    func testLateAddressIsDiscardedAfterLocationIsDisabled() {
        let now = Date(timeIntervalSince1970: 100_000)
        let geocoder = FakePreviewGeocoder()
        let service = AddressPreviewService(makeGeocoder: { geocoder }, clock: { now })
        service.update(location: fix(-17.9, time: now), enabled: true, now: now)
        service.update(location: nil, enabled: false, now: now)
        XCTAssertTrue(geocoder.cancelled)
        geocoder.completion?("Endereço antigo")
        XCTAssertNil(service.address)
        XCTAssertNil(service.current(for: fix(-17.9, time: now), at: now))
    }

    func testCachedAddressIsNotUsedAfterMovingOrExpiry() {
        let now = Date(timeIntervalSince1970: 100_000)
        let geocoder = FakePreviewGeocoder()
        let service = AddressPreviewService(makeGeocoder: { geocoder }, clock: { now })
        let original = fix(-17.9, time: now)
        service.update(location: original, enabled: true, now: now)
        geocoder.completion?("Endereço de teste")
        XCTAssertEqual(service.current(for: original, at: now), "Endereço de teste")
        XCTAssertNil(service.current(for: fix(-17.901, time: now), at: now))
        let later = now.addingTimeInterval(61)
        XCTAssertNil(service.current(for: fix(-17.9, time: later), at: later))
    }

    func testAutomaticLookupsRespectMinimumInterval() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(AddressPreviewService.mayRequest(lastAttempt: nil, now: now))
        XCTAssertFalse(AddressPreviewService.mayRequest(lastAttempt: now.addingTimeInterval(-14), now: now))
        XCTAssertTrue(AddressPreviewService.mayRequest(lastAttempt: now.addingTimeInterval(-15), now: now))
        XCTAssertTrue(AddressPreviewService.mayRequest(lastAttempt: now.addingTimeInterval(10), now: now))
    }

    func testCachedAddressRequiresEnabledValidLocationAndIsReused() {
        let now = Date()
        let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.9, longitude: -51.7), altitude: 700,
            horizontalAccuracy: 8, verticalAccuracy: 5, timestamp: now)
        let disabled = StampSnapshot(capturedAt: now, gpsEnabled: false, addressEnabled: true,
            cachedAddress: "Endereço de teste", location: fix, heading: nil)
        XCTAssertNil(disabled.cachedAddress)
        let enabled = StampSnapshot(capturedAt: now, gpsEnabled: true, addressEnabled: true,
            cachedAddress: "Endereço de teste", location: fix, heading: nil)
        var returned: String?
        StampAddress.load(snapshot: enabled, queue: .main) { returned = $0 }
        XCTAssertEqual(returned, "Endereço de teste")
    }
}
