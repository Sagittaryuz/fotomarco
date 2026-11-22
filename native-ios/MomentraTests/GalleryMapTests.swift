import XCTest
@testable import Momentra

final class GalleryMapTests: XCTestCase {
    func testNearbyPhotosSeparateWhenZoomingIn() {
        let farA = GalleryMapBinning.key(latitude: -17.88, longitude: -51.71, span: 40)
        let farB = GalleryMapBinning.key(latitude: -17.87, longitude: -51.70, span: 40)
        let nearA = GalleryMapBinning.key(latitude: -17.88, longitude: -51.71, span: 0.01)
        let nearB = GalleryMapBinning.key(latitude: -17.87, longitude: -51.70, span: 0.01)
        XCTAssertEqual(farA, farB)
        XCTAssertNotEqual(nearA, nearB)
    }
}
