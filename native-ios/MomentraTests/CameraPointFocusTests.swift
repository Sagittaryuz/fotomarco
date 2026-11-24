import AVFoundation
import XCTest
@testable import Momentra

final class CameraPointFocusTests: XCTestCase {
    func testZoomFocusPrefersContinuousAndChecksDeviceSupport() {
        XCTAssertEqual(CameraPointFocus.zoomFocusMode(pointSupported: true) { _ in true }, .continuousAutoFocus)
        XCTAssertEqual(CameraPointFocus.zoomFocusMode(pointSupported: true) { $0 == .autoFocus }, .autoFocus)
        XCTAssertNil(CameraPointFocus.zoomFocusMode(pointSupported: false) { _ in true })
        XCTAssertNil(CameraPointFocus.zoomFocusMode(pointSupported: true) { _ in false })
    }

    func testOnlyNormalizedFiniteDevicePointsAreUsable() {
        XCTAssertTrue(CameraPointFocus.isValid(CGPoint(x: 0.25, y: 0.8)))
        XCTAssertTrue(CameraPointFocus.isValid(CGPoint(x: 1, y: 0)))
        XCTAssertFalse(CameraPointFocus.isValid(CGPoint(x: 1.1, y: 0.8)))
        XCTAssertFalse(CameraPointFocus.isValid(CGPoint(x: 0.5, y: -0.1)))
        XCTAssertFalse(CameraPointFocus.isValid(CGPoint(x: CGFloat.infinity, y: 0)))
    }

    func testContinuousFocusIsFallbackWhenSingleFocusIsUnavailable() {
        XCTAssertEqual(CameraPointFocus.focusMode(pointSupported: true) { _ in true }, .autoFocus)
        XCTAssertEqual(CameraPointFocus.focusMode(pointSupported: true) { $0 == .continuousAutoFocus },
                       .continuousAutoFocus)
        XCTAssertNil(CameraPointFocus.focusMode(pointSupported: true) { _ in false })
    }

    func testExposureCanUseTheTappedPointOnAFixedFocusLens() {
        XCTAssertNil(CameraPointFocus.focusMode(pointSupported: false) { _ in true })
        XCTAssertEqual(CameraPointFocus.exposureMode(pointSupported: true) { _ in true }, .continuousAutoExposure)
        XCTAssertEqual(CameraPointFocus.exposureMode(pointSupported: true) { $0 == .autoExpose }, .autoExpose)
        XCTAssertNil(CameraPointFocus.exposureMode(pointSupported: false) { _ in true })
    }
}
