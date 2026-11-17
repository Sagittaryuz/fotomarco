import XCTest
import CoreLocation
@testable import Momentra

final class StampSnapshotTests: XCTestCase {
    func testDisabledGPSNeverAppearsInStamp() {
        let now = Date()
        let location = CLLocation(latitude: -17.9, longitude: -51.7)
        let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: false, mapEnabled: true, addressEnabled: true, location: location, heading: nil)
        XCTAssertNil(snapshot.location)
        XCTAssertFalse(snapshot.mapEnabled)
        XCTAssertFalse(snapshot.addressEnabled)
        XCTAssertTrue(snapshot.lines.contains("Localização desativada"))
        let completed = expectation(description: "address skipped when GPS disabled")
        StampAddress.load(snapshot: snapshot, queue: .main) { address in
            XCTAssertNil(address)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
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

    func testProfileTextIsBoundedAndSingleLine() {
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, title: String(repeating: "A", count: 45), note: "nota\nseguinte", location: nil, heading: nil)
        XCTAssertEqual(snapshot.title.count, 40)
        XCTAssertEqual(snapshot.note, "nota seguinte")
        XCTAssertEqual(snapshot.lines.first, snapshot.title)
    }

    func testStampPositionHasSafeDefault() {
        let top = StampSnapshot(capturedAt: Date(), gpsEnabled: false, position: "top", location: nil, heading: nil)
        let invalid = StampSnapshot(capturedAt: Date(), gpsEnabled: false, position: "unexpected", location: nil, heading: nil)
        XCTAssertEqual(top.position, "top")
        XCTAssertEqual(invalid.position, "bottom")
    }
}
