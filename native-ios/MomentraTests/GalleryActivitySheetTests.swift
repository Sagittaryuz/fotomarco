import Foundation
import XCTest
@testable import Momentra

final class GalleryActivitySheetTests: XCTestCase {
    func testCompletedActivityReturnsToGallery() {
        XCTAssertTrue(GalleryActivitySheet.succeeded(completed: true, error: nil))
    }

    func testCancellationKeepsGallerySelection() {
        XCTAssertFalse(GalleryActivitySheet.succeeded(completed: false, error: nil))
    }

    func testActivityErrorKeepsGallerySelection() {
        let error = NSError(domain: "GalleryActivitySheetTests", code: 1)
        XCTAssertFalse(GalleryActivitySheet.succeeded(completed: true, error: error))
        XCTAssertFalse(GalleryActivitySheet.succeeded(completed: false, error: error))
    }
}
