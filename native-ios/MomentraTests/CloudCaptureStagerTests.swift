import XCTest
@testable import Momentra

final class CloudCaptureStagerTests: XCTestCase {
    func testStagesIdempotentlyAndRejectsChangedFileOrOtherAccount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let originals = root.appendingPathComponent("Originals"), processed = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        let original = originals.appendingPathComponent(id.uuidString + ".jpg")
        let stamped = processed.appendingPathComponent(id.uuidString + ".jpg")
        try Data("original".utf8).write(to: original)
        try Data("stamped".utf8).write(to: stamped)
        let hash = CloudCaptureQueue.ownerHash("person-a")
        try CloudCaptureStager.stage(root: root, captureID: id, ownerHash: hash, originalExtension: "JPG")
        try CloudCaptureStager.stage(root: root, captureID: id, ownerHash: hash, originalExtension: "jpg")
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        XCTAssertEqual(try queue.entry(id: id).phase, .ready)
        XCTAssertThrowsError(try CloudCaptureStager.stage(root: root, captureID: id,
                            ownerHash: CloudCaptureQueue.ownerHash("person-b"), originalExtension: "jpg"))
        try Data("changed".utf8).write(to: stamped)
        XCTAssertThrowsError(try CloudCaptureStager.stage(root: root, captureID: id, ownerHash: hash, originalExtension: "jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
    }

    func testInterruptedStagingCanResumeAfterFileAppears() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), hash = CloudCaptureQueue.ownerHash("person-a")
        let originals = root.appendingPathComponent("Originals"), processed = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: originals.appendingPathComponent(id.uuidString + ".jpg"))
        XCTAssertThrowsError(try CloudCaptureStager.stage(root: root, captureID: id, ownerHash: hash, originalExtension: "jpg"))
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        XCTAssertEqual(try queue.entry(id: id).phase, .awaitingPhoto)
        try Data("stamped".utf8).write(to: processed.appendingPathComponent(id.uuidString + ".jpg"))
        try CloudCaptureStager.stage(root: root, captureID: id, ownerHash: hash, originalExtension: "jpg")
        XCTAssertEqual(try queue.entry(id: id).phase, .ready)
    }
}
