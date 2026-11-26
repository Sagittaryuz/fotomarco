import Foundation
import XCTest
@testable import Momentra

final class GalleryActivitySheetTests: XCTestCase {
    func testPercentDoesNotRoundUpBeforeAllItemsAreReady() {
        XCTAssertEqual(GalleryShareProgress(completed: 9, total: 10, currentFraction: 0.99).percent, 99)
        XCTAssertEqual(GalleryShareProgress(completed: 10, total: 10).percent, 100)
    }
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

    @MainActor
    func testTransferProgressIsReportedBeforeTheFileIsComplete() async throws {
        var reported: [GalleryShareProgress] = []
        let batch = try await GalleryShareBatch.prepareWithTransferProgress([1], progress: { reported.append($0) }) {
            _, directory, progress in
            progress(0.5)
            try await Task.sleep(nanoseconds: 20_000_000)
            let output = directory.appendingPathComponent("photo.jpg")
            try Data([1]).write(to: output)
            return output
        }
        withExtendedLifetime(batch) {
            XCTAssertTrue(reported.contains { $0.fraction == 0.5 && $0.completed == 0 })
            XCTAssertEqual(reported.last?.fraction, 1)
        }
    }
}
