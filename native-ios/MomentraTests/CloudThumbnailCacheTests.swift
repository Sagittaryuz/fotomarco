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
        let selected = try XCTUnwrap(CloudThumbnailCache.latestCapturePreview(root: root))
        XCTAssertEqual(selected.file, root.appendingPathComponent("CloudThumbnails").appendingPathComponent(id.uuidString + ".jpg"))
    }
    func testShareCacheKeepsNewestFullResolutionCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldID = UUID(), newID = UUID()
        let old = root.appendingPathComponent("old.jpg"), new = root.appendingPathComponent("new.jpg")
        try Data([1, 2, 3]).write(to: old); try Data([4, 5, 6, 7]).write(to: new)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: new.path)
        try CloudThumbnailCache.cacheShareOriginal(root: root, captureID: newID, source: new)
        try CloudThumbnailCache.cacheShareOriginal(root: root, captureID: oldID, source: old)
        XCTAssertNil(CloudThumbnailCache.shareOriginal(root: root, captureID: oldID))
        let cached = try XCTUnwrap(CloudThumbnailCache.shareOriginal(root: root, captureID: newID))
        XCTAssertEqual(try Data(contentsOf: cached), try Data(contentsOf: new))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
    }
}
