import XCTest
import UIKit
@testable import Momentra

final class CloudCaptureCleanupTests: XCTestCase {
    private func fixture(_ root: URL) throws -> (UUID, CloudCaptureQueue, URL, URL) {
        let id = UUID()
        let a = root.appendingPathComponent("Originals"), b = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let original = a.appendingPathComponent(id.uuidString + ".jpg")
        let stamped = b.appendingPathComponent(id.uuidString + ".jpg")
        try Data("original".utf8).write(to: original)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: stamped)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: "person-a", originalExtension: "jpg")
        try queue.markReady(id: id, original: original, processed: stamped)
        try queue.markVerified(id: id, originalMediaID: "original-id", processedMediaID: "stamped-id")
        return (id, queue, original, stamped)
    }

    func testRetainsFilesWhenEitherRemoteItemIsUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (id, queue, original, stamped) = try fixture(root)
        let cleanup = CloudCaptureCleanup(queue: queue, root: root, accountIsCurrent: { $0 == "person-a" },
                                          verify: { $0 == "original-id" })
        let result = await cleanup.clean(id: id, owner: "person-a", cloudOnlyEnabled: true)
        XCTAssertEqual(result, .retained)
        XCTAssertEqual(try queue.entry(id: id).phase, .verified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
    }

    func testResumesAfterInterruptionOnlyForMatchingAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (id, queue, original, stamped) = try fixture(root)
        try queue.beginCleanup(id: id, owner: "person-a")
        try FileManager.default.removeItem(at: original)
        let cleanup = CloudCaptureCleanup(queue: queue, root: root, accountIsCurrent: { $0 == "person-a" },
                                          verify: { _ in true })
        let wrong = await cleanup.clean(id: id, owner: "person-b", cloudOnlyEnabled: true)
        XCTAssertEqual(wrong, .retained)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
        let resumed = await cleanup.clean(id: id, owner: "person-a", cloudOnlyEnabled: true)
        XCTAssertEqual(resumed, .cleaned)
        XCTAssertEqual(try queue.entry(id: id).phase, .cleaned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stamped.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("CloudThumbnails")
            .appendingPathComponent(id.uuidString + ".jpg").path))
    }

    func testChangedLocalCopyBlocksCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (id, queue, original, stamped) = try fixture(root)
        try Data("changed".utf8).write(to: stamped)
        let cleanup = CloudCaptureCleanup(queue: queue, root: root, accountIsCurrent: { _ in true },
                                          verify: { _ in true })
        let result = await cleanup.clean(id: id, owner: "person-a", cloudOnlyEnabled: true)
        XCTAssertEqual(result, .retained)
        XCTAssertEqual(try queue.entry(id: id).phase, .verified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
    }
}
