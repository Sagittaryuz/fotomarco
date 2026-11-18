import XCTest
@testable import Momentra

final class CloudCaptureQueueTests: XCTestCase {
    private func files(root: URL, id: UUID, ext: String) throws -> (URL, URL) {
        let originals = root.appendingPathComponent("Originals", isDirectory: true)
        let processed = root.appendingPathComponent("Processed", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        let a = originals.appendingPathComponent(id.uuidString + "." + ext)
        let b = processed.appendingPathComponent(id.uuidString + ".jpg")
        try Data("original".utf8).write(to: a)
        try Data("com carimbo".utf8).write(to: b)
        return (a, b)
    }

    func testQueuePersistsFingerprintsAndSeparatesAccounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: "account-a", originalExtension: "HEIC")
        let (original, processed) = try files(root: root, id: id, ext: "heic")
        try queue.markReady(id: id, original: original, processed: processed)
        let restored = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        let item = try XCTUnwrap(restored.entries(for: "account-a").first)
        XCTAssertEqual(item.phase, .ready)
        XCTAssertNotNil(item.originalFingerprint)
        XCTAssertNotNil(item.processedFingerprint)
        XCTAssertTrue(try restored.entries(for: "account-b").isEmpty)
    }

    func testOnlyTwoConfirmedRemoteItemsCanMarkVerified() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: "account", originalExtension: "jpg")
        XCTAssertThrowsError(try queue.markVerified(id: id, originalMediaID: "a", processedMediaID: "b"))
        let (original, processed) = try files(root: root, id: id, ext: "jpg")
        try queue.markReady(id: id, original: original, processed: processed)
        XCTAssertThrowsError(try queue.markVerified(id: id, originalMediaID: "", processedMediaID: "b"))
        try queue.markVerified(id: id, originalMediaID: "a", processedMediaID: "b")
        XCTAssertEqual(try queue.entries(for: "account").first?.phase, .verified)
        XCTAssertTrue(try queue.verifiedFilesStillMatch(id: id, owner: "account", original: original, processed: processed))
        XCTAssertFalse(try queue.verifiedFilesStillMatch(id: id, owner: "other", original: original, processed: processed))
        try Data("alterado".utf8).write(to: processed)
        XCTAssertFalse(try queue.verifiedFilesStillMatch(id: id, owner: "account", original: original, processed: processed))
        XCTAssertThrowsError(try queue.markReady(id: id, original: original, processed: processed))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: processed.path))
    }

    func testUncertainUploadCannotBeDeclaredVerified() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: "account", originalExtension: "heic")
        let (original, processed) = try files(root: root, id: id, ext: "heic")
        try queue.markReady(id: id, original: original, processed: processed)
        try queue.markUncertain(id: id)
        XCTAssertThrowsError(try queue.markVerified(id: id, originalMediaID: "a", processedMediaID: "b"))
        XCTAssertEqual(try queue.entries(for: "account").first?.phase, .uncertain)
    }

    func testRejectsFileOutsideCaptureDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: "account", originalExtension: "jpg")
        let (original, processed) = try files(root: root, id: id, ext: "jpg")
        XCTAssertThrowsError(try queue.markReady(id: id, original: processed, processed: original))
        XCTAssertEqual(try queue.entries(for: "account").first?.phase, .awaitingPhoto)
    }
}
