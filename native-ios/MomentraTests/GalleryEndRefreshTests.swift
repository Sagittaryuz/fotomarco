import XCTest
@testable import Momentra

final class GalleryEndRefreshTests: XCTestCase {
    func testOnlyAnUpwardDragPastTheBottomThresholdRequestsRefresh() {
        let upward = CGPoint(x: 5, y: -150)
        XCTAssertFalse(GalleryEndRefresh.reached(offset: 300, maximum: 300, fingerMovement: upward))
        XCTAssertFalse(GalleryEndRefresh.reached(offset: 353, maximum: 300, fingerMovement: upward))
        XCTAssertTrue(GalleryEndRefresh.reached(offset: 354, maximum: 300, fingerMovement: upward))
        XCTAssertFalse(GalleryEndRefresh.reached(offset: 400, maximum: 300, fingerMovement: CGPoint(x: 180, y: -40)))
        XCTAssertFalse(GalleryEndRefresh.reached(offset: 400, maximum: 300, fingerMovement: CGPoint(x: 0, y: 150)))
    }
}
