import XCTest
import CoreLocation
@testable import Momentra

final class StampSnapshotTests: XCTestCase {
    func testDisabledGPSNeverAppearsInStamp() {
        let now = Date()
        let location = CLLocation(latitude: -17.9, longitude: -51.7)
        let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: false, mapEnabled: true, location: location, heading: nil)
        XCTAssertNil(snapshot.location)
        XCTAssertFalse(snapshot.mapEnabled)
        XCTAssertTrue(snapshot.lines.contains("Localização desativada"))
    }

    func testOldOrFutureLocationIsRejected() {
        let now = Date()
        func makeLocation(_ time: Date) -> CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.9, longitude: -51.7), altitude: 700, horizontalAccuracy: 8, verticalAccuracy: 5, timestamp: time)
        }
        XCTAssertNil(StampSnapshot(capturedAt: now, gpsEnabled: true, location: makeLocation(now.addingTimeInterval(-61)), heading: nil).location)
        XCTAssertNil(StampSnapshot(capturedAt: now, gpsEnabled: true, location: makeLocation(now.addingTimeInterval(1)), heading: nil).location)
        let fresh = StampSnapshot(capturedAt: now, gpsEnabled: true, location: makeLocation(now), heading: nil)
        XCTAssertNotNil(fresh.location)
        XCTAssertTrue(fresh.lines.contains { $0.contains("Precisão: ±8 m") })
        XCTAssertTrue(fresh.lines.contains { $0.contains("Altitude:") })
    }
}
