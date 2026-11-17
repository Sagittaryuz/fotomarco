import XCTest
import CoreLocation
@testable import Momentra

@MainActor
final class AddressPreviewTests: XCTestCase {
    func testAutomaticLookupsRespectMinimumInterval() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(AddressPreviewService.mayRequest(lastAttempt: nil, now: now))
        XCTAssertFalse(AddressPreviewService.mayRequest(lastAttempt: now.addingTimeInterval(-59), now: now))
        XCTAssertTrue(AddressPreviewService.mayRequest(lastAttempt: now.addingTimeInterval(-60), now: now))
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
