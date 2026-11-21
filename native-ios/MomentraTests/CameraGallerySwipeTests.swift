import XCTest
import UIKit
@testable import Momentra

final class CameraGallerySwipeTests: XCTestCase {
    func testOnlyDeliberateRightwardHorizontalSwipeOpensGallery() {
        XCTAssertTrue(CameraGallerySwipe.qualifies(CGSize(width: 90, height: 20)))
        XCTAssertFalse(CameraGallerySwipe.qualifies(CGSize(width: 81, height: 0)))
        XCTAssertFalse(CameraGallerySwipe.qualifies(CGSize(width: -120, height: 0)))
        XCTAssertFalse(CameraGallerySwipe.qualifies(CGSize(width: 100, height: 90)))
    }
}
