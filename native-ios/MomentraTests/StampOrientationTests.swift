import XCTest
import UIKit
@testable import Momentra

final class StampOrientationTests: XCTestCase {
    func testBothLandscapeDirectionsWhenInterfaceRemainsPortrait() {
        XCTAssertEqual(StampOrientation.angle(device: .landscapeLeft, interface: .portrait), 90)
        XCTAssertEqual(StampOrientation.angle(device: .landscapeRight, interface: .portrait), -90)
    }

    func testRotatedInterfaceDoesNotRotateStampTwice() {
        XCTAssertEqual(StampOrientation.angle(device: .landscapeLeft, interface: .landscapeRight), 0)
        XCTAssertEqual(StampOrientation.angle(device: .landscapeRight, interface: .landscapeLeft), 0)
    }
}
