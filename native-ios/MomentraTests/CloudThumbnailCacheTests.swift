import UIKit
import XCTest
@testable import Momentra

final class CloudThumbnailCacheTests: XCTestCase {
    func testLatestPreviewSurvivesCloudOnlyCleanupAndSkipsUnreadableFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let context = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80))
        let photo = context.jpegData(withCompressionQuality: 0.8) { renderer in
            UIColor.blue.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let processed = try ProcessedFileStore.save(photo, captureID: id, root: root)
        try CloudThumbnailCache.ensure(root: root, captureID: id, source: processed)
        try FileManager.default.removeItem(at: processed)
        let invalid = try ProcessedFileStore.save(Data([0]), root: root)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: invalid.path)
        XCTAssertNotNil(CloudThumbnailCache.latestCapturePreview(root: root))
    }
}
