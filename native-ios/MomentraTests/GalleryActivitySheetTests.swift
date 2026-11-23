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
    @MainActor
    func testPreparationReportsOnlyCompletedItems() async throws {
        var reported: [GalleryShareProgress] = []
        let batch = try await GalleryShareBatch.prepare([1, 2, 3], progress: { completed, total in
            reported.append(GalleryShareProgress(completed: completed, total: total))
        }) { item, directory in
            let output = directory.appendingPathComponent("photo-\(item).jpg")
            try Data([UInt8(item)]).write(to: output)
            return output
        }
        withExtendedLifetime(batch) {
            XCTAssertEqual(reported, [GalleryShareProgress(completed: 0, total: 3),
                                      GalleryShareProgress(completed: 1, total: 3),
                                      GalleryShareProgress(completed: 2, total: 3),
                                      GalleryShareProgress(completed: 3, total: 3)])
        }
    }

    @MainActor
    func testFailedPreparationDoesNotReportTheFailedItem() async {
        var completed: [Int] = []
        do {
            _ = try await GalleryShareBatch.prepare([1, 2], progress: { done, _ in completed.append(done) }) { item, directory in
                if item == 2 { throw NSError(domain: "share-test", code: 1) }
                let output = directory.appendingPathComponent("photo.jpg")
                try Data([1]).write(to: output)
                return output
            }
            XCTFail("Expected preparation failure")
        } catch { XCTAssertEqual(completed, [0, 1]) }
    }
}
