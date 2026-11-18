import XCTest
@testable import Momentra

final class CaptureMotionTests: XCTestCase {
    func testPortraitFrameFitsCenteredInGalleryThumbnail() {
        let bounds = CGRect(x: 20, y: 620, width: 52, height: 52)
        XCTAssertEqual(CaptureMotion.aspectFit(CGSize(width: 300, height: 400), in: bounds),
                       CGRect(x: 26.5, y: 620, width: 39, height: 52))
    }

    func testLandscapeFrameFitsCenteredInGalleryThumbnail() {
        let bounds = CGRect(x: 20, y: 240, width: 52, height: 52)
        XCTAssertEqual(CaptureMotion.aspectFit(CGSize(width: 400, height: 300), in: bounds),
                       CGRect(x: 20, y: 246.5, width: 52, height: 39))
    }

    func testElapsedTimeUsesMonotonicInstantsAndFloorsPartialSeconds() {
        let start = ContinuousClock.now
        XCTAssertEqual(CaptureMotion.elapsedSeconds(from: start, to: start - .seconds(1)), 0)
        XCTAssertEqual(CaptureMotion.elapsedSeconds(from: start, to: start + .milliseconds(2999)), 2)
    }

    func testTimerShowsHoursOnlyWhenNeeded() {
        XCTAssertEqual(CaptureMotion.timerLabel(seconds: 0), "00:00")
        XCTAssertEqual(CaptureMotion.timerLabel(seconds: 3599), "59:59")
        XCTAssertEqual(CaptureMotion.timerLabel(seconds: 3661), "01:01:01")
    }
}
