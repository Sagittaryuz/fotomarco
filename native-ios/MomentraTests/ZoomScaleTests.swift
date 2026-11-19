import XCTest
@testable import Momentra

final class ZoomScaleTests: XCTestCase {
    func testSingleCameraDoesNotInventUltraWide() {
        let scale = ZoomScale(wideFactor: 1, minimum: 1, maximum: 3)
        XCTAssertEqual(scale.options, [1, 2])
        XCTAssertNil(scale.deviceFactor(for: 0.5))
    }

    func testVirtualCameraMapsDisplayedZoomToDeviceFactors() {
        let scale = ZoomScale(wideFactor: 2, minimum: 1, maximum: 6)
        XCTAssertEqual(scale.options, [0.5, 1, 2])
        XCTAssertEqual(scale.deviceFactor(for: 0.5), 1)
        XCTAssertEqual(scale.deviceFactor(for: 1), 2)
        XCTAssertEqual(scale.deviceFactor(for: 3), 6)
    }

    func testRoundedUltraWideAndUnavailableZoom() {
        let scale = ZoomScale(wideFactor: 1.96, minimum: 1, maximum: 4)
        XCTAssertEqual(scale.deviceFactor(for: 0.5), 1)
        XCTAssertNil(scale.deviceFactor(for: 3))
        XCTAssertNil(ZoomScale(wideFactor: 0, minimum: 1, maximum: 4).deviceFactor(for: 1))
    }

    func testPinchZoomAccumulatesAndReversesAtEitherLimit() {
        let range: ClosedRange<CGFloat> = 0.5...4
        var pinch = PreviewPinchZoom(value: 2)
        pinch.move(to: 1.1, range: range)
        XCTAssertEqual(pinch.value, 2.2, accuracy: 0.001)
        pinch.move(to: 3, range: range)
        XCTAssertEqual(pinch.value, 4)
        pinch.move(to: 2.4, range: range)
        XCTAssertEqual(pinch.value, 3.2, accuracy: 0.001)
        pinch.move(to: 0.2, range: range)
        XCTAssertEqual(pinch.value, 0.5)
        pinch.move(to: 0.4, range: range)
        XCTAssertEqual(pinch.value, 1, accuracy: 0.001)
        pinch.move(to: .nan, range: range)
        XCTAssertEqual(pinch.value, 1, accuracy: 0.001)
    }

    func testQuickCaptureDragZoomIsSmoothAndBounded() {
        XCTAssertEqual(QuickCaptureZoom.value(start: 1, verticalTranslation: -180, range: 0.5...8), 2, accuracy: 0.001)
        XCTAssertEqual(QuickCaptureZoom.value(start: 1, verticalTranslation: 180, range: 0.5...8), 0.5, accuracy: 0.001)
        XCTAssertEqual(QuickCaptureZoom.value(start: 1, verticalTranslation: -4000, range: 0.5...8), 8, accuracy: 0.001)
    }

    func testHeldHorizontalDragKeepsAdjustingAndReversesWithoutCrossingStart() {
        let range: ClosedRange<CGFloat> = 0.5...8
        var zoom = ContinuousCameraZoom(value: 1)
        XCTAssertEqual(zoom.advance(seconds: 1, range: range), 1)
        zoom.move(to: 65, range: range)
        let moved = zoom.value
        XCTAssertGreaterThan(zoom.advance(seconds: 0.5, range: range), moved)
        zoom.move(to: 45, range: range)
        let reversed = zoom.value
        XCTAssertLessThan(zoom.advance(seconds: 0.5, range: range), reversed)
    }

    func testContinuousDragClampsAndCanLeaveEitherLimit() {
        let range: ClosedRange<CGFloat> = 0.5...8
        var zoom = ContinuousCameraZoom(value: 2)
        zoom.move(to: 100, range: range)
        XCTAssertEqual(zoom.advance(seconds: 20, range: range), 8)
        zoom.move(to: 70, range: range)
        XCTAssertLessThan(zoom.value, 8)
        XCTAssertEqual(zoom.advance(seconds: 40, range: range), 0.5)
        zoom.move(to: 95, range: range)
        XCTAssertGreaterThan(zoom.value, 0.5)
    }
}
