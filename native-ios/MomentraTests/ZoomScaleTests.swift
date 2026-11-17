import XCTest
@testable import Momentra

final class ZoomScaleTests: XCTestCase {
    func testSingleCameraDoesNotInventUltraWide() {
        let scale = ZoomScale(wideFactor: 1, minimum: 1, maximum: 3)
        XCTAssertEqual(scale.options, [1, 2, 3])
        XCTAssertNil(scale.deviceFactor(for: 0.5))
    }

    func testVirtualCameraMapsDisplayedZoomToDeviceFactors() {
        let scale = ZoomScale(wideFactor: 2, minimum: 1, maximum: 6)
        XCTAssertEqual(scale.options, [0.5, 1, 2, 3])
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
}
