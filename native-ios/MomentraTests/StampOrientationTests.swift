import XCTest
import UIKit
@testable import Momentra

final class StampOrientationTests: XCTestCase {
    func testGravityRecognizesBothLandscapeDirectionsAndPortrait() {
        XCTAssertEqual(StampOrientation.deviceOrientation(gravityX: -0.8, gravityY: -0.1), .landscapeLeft)
        XCTAssertEqual(StampOrientation.deviceOrientation(gravityX: 0.8, gravityY: -0.1), .landscapeRight)
        XCTAssertEqual(StampOrientation.deviceOrientation(gravityX: 0.1, gravityY: -0.9), .portrait)
        XCTAssertEqual(StampOrientation.deviceOrientation(gravityX: 0.1, gravityY: 0.9), .portraitUpsideDown)
    }

    func testGravityRetainsLastOrientationWhenFlatOrAmbiguous() {
        XCTAssertNil(StampOrientation.deviceOrientation(gravityX: 0.03, gravityY: 0.04))
        XCTAssertNil(StampOrientation.deviceOrientation(gravityX: 0.6, gravityY: 0.6))
        XCTAssertNil(StampOrientation.deviceOrientation(gravityX: .nan, gravityY: 0.8))
    }
    func testApplicationSupportsOnlyPortraitInterface() {
        let orientations = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations~iphone") as? [String]
        XCTAssertEqual(orientations, ["UIInterfaceOrientationPortrait"])
    }
    func testBothLandscapeDirectionsWhenInterfaceRemainsPortrait() {
        XCTAssertEqual(StampOrientation.angle(device: .landscapeLeft, interface: .portrait), 90)
        XCTAssertEqual(StampOrientation.angle(device: .landscapeRight, interface: .portrait), -90)
    }

    func testRotatedInterfaceDoesNotRotateStampTwice() {
        XCTAssertEqual(StampOrientation.angle(device: .landscapeLeft, interface: .landscapeRight), 0)
        XCTAssertEqual(StampOrientation.angle(device: .landscapeRight, interface: .landscapeLeft), 0)
    }
}
