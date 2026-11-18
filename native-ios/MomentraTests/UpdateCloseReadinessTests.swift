import XCTest
@testable import Momentra

final class UpdateCloseReadinessTests: XCTestCase {
    func testNeverCloseWhileCaptureOrUploadIsActive() {
        func allowed(_ c: Bool = false, _ s: Bool = false, _ r: Bool = false, _ f: Bool = false, _ videos: Int = 0, _ cloud: Bool = false) -> Bool {
            UpdateCloseReadiness.allowsClose(capturing: c, switching: s, recording: r, finishing: f, processingVideos: videos, cloudBusy: cloud)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(true))
        XCTAssertFalse(allowed(false, true))
        XCTAssertFalse(allowed(false, false, true))
        XCTAssertFalse(allowed(false, false, false, true))
        XCTAssertFalse(allowed(false, false, false, false, 1))
        XCTAssertFalse(allowed(false, false, false, false, 0, true))
    }
}
