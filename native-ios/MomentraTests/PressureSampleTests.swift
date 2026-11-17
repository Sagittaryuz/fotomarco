import XCTest
@testable import Momentra

final class PressureSampleTests: XCTestCase {
    func testSnapshotRejectsStaleFutureAndInvalidPressure() {
        let now = Date()
        let stale = PressureSample(hectopascals: 922.8, observedAt: now.addingTimeInterval(-11))
        let future = PressureSample(hectopascals: 922.8, observedAt: now.addingTimeInterval(1))
        let invalid = PressureSample(hectopascals: .nan, observedAt: now)
        for sample in [stale, future, invalid] {
            let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: false, pressure: sample, location: nil, heading: nil)
            XCTAssertNil(snapshot.pressure)
            XCTAssertFalse(snapshot.lines.contains { $0.contains("Pressão") })
        }
        let fresh = PressureSample(hectopascals: 922.8, observedAt: now)
        let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: false, pressure: fresh, location: nil, heading: nil)
        XCTAssertNotNil(snapshot.pressure)
        XCTAssertTrue(snapshot.lines.contains { $0.contains("hPa") })
    }
}
