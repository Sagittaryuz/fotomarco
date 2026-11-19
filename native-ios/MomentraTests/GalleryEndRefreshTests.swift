import XCTest
@testable import Momentra

final class GalleryEndRefreshTests: XCTestCase {
    func testOnlyAnUpwardDragPastTheBottomThresholdRequestsRefresh() {
        let upward = CGPoint(x: 5, y: -150)
        XCTAssertFalse(GalleryEndRefresh.reached(offset: 290, maximum: 300, initialDistance: 80, fingerMovement: upward))
        XCTAssertFalse(GalleryEndRefresh.reached(offset: 302, maximum: 300, initialDistance: 100, fingerMovement: upward))
        XCTAssertTrue(GalleryEndRefresh.reached(offset: 300, maximum: 300, initialDistance: 85, fingerMovement: upward))
        XCTAssertTrue(GalleryEndRefresh.reached(offset: 0, maximum: 0, initialDistance: 0, fingerMovement: upward))
        XCTAssertFalse(GalleryEndRefresh.reached(offset: 310, maximum: 300, initialDistance: 0, fingerMovement: CGPoint(x: 180, y: -75)))
        XCTAssertFalse(GalleryEndRefresh.reached(offset: 310, maximum: 300, initialDistance: 0, fingerMovement: CGPoint(x: 0, y: 150)))
    }
}
