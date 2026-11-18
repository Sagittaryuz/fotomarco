import XCTest
import UIKit
@testable import Momentra

private actor PairTransportMock {
    var calls: [UUID] = []
    var holdStamped = true
    func upload(_ id: UUID) -> PersonalUploadOutcome {
        calls.append(id)
        if calls.count.isMultiple(of: 2) && holdStamped { return .verificationPending("stamped-id") }
        return .verified(calls.count.isMultiple(of: 2) ? "stamped-id" : "original-id")
    }
    func allowStamped() { holdStamped = false }
    func received() -> [UUID] { calls }
}

private actor PairReceiptTransport: PersonalPhotoTransport {
    var creations = 0
    var stampedVerified = false
    func uploadBytes(_ data: Data) async throws -> String { "upload-token" }
    func createItem(uploadToken: String, filename: String) async throws -> String {
        creations += 1
        return "media-" + String(creations)
    }
    func verifyItem(id: String) async throws -> Bool {
        id != "media-2" || stampedVerified
    }
    func allowVerification() { stampedVerified = true }
    func creationCount() -> Int { creations }
}

private actor SuspendedPairTransport {
    private var continuation: CheckedContinuation<PersonalUploadOutcome, Never>?
    func upload() async -> PersonalUploadOutcome {
        await withCheckedContinuation { continuation = $0 }
    }
    func started() -> Bool { continuation != nil }
    func finish() { continuation?.resume(returning: .verified("original-id")); continuation = nil }
}

final class CloudPairUploadCoordinatorTests: XCTestCase {
    func testRetriesBothReceiptsWithoutRemovingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), owner = "person-a"
        let originalDir = root.appendingPathComponent("Originals")
        let stampedDir = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: originalDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stampedDir, withIntermediateDirectories: true)
        let original = originalDir.appendingPathComponent(id.uuidString + ".jpg")
        let stamped = stampedDir.appendingPathComponent(id.uuidString + ".jpg")
        try Data("original pixels".utf8).write(to: original)
        try Data("stamped pixels".utf8).write(to: stamped)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: owner, originalExtension: "jpg")
        try queue.markReady(id: id, original: original, processed: stamped)
        let mock = PairTransportMock()
        let coordinator = CloudPairUploadCoordinator(queue: queue, root: root, accountIsCurrent: { $0 == owner }) {
            _, receipt, _, _, _ in await mock.upload(receipt)
        }
        let first = await coordinator.send(id: id, owner: owner, personalConsent: true,
                                           originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(first, .pending)
        XCTAssertEqual(try queue.entries(for: owner).first?.phase, .ready)
        await mock.allowStamped()
        let second = await coordinator.send(id: id, owner: owner, personalConsent: true,
                                            originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(second, .verified(original: "original-id", stamped: "stamped-id"))
        let calls = await mock.received()
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(calls[0], calls[2])
        XCTAssertEqual(calls[1], calls[3])
        XCTAssertNotEqual(calls[0], calls[1])
        XCTAssertEqual(try queue.entries(for: owner).first?.phase, .verified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
    }

    func testDoesNotUploadWithoutConsentOrForAnotherAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mock = PairTransportMock()
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        let coordinator = CloudPairUploadCoordinator(queue: queue, root: root, accountIsCurrent: { $0 == "person-a" }) {
            _, receipt, _, _, _ in await mock.upload(receipt)
        }
        let denied = await coordinator.send(id: UUID(), owner: "person-a", personalConsent: false,
                                            originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        let wrongAccount = await coordinator.send(id: UUID(), owner: "person-b", personalConsent: true,
                                                  originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(denied, .unavailable)
        XCTAssertEqual(wrongAccount, .unavailable)
        let calls = await mock.received()
        XCTAssertTrue(calls.isEmpty)
    }
    func testChangedFileRemainsLocalAndIsNotUploaded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), owner = "person-a"
        let a = root.appendingPathComponent("Originals"), b = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let original = a.appendingPathComponent(id.uuidString + ".jpg")
        let stamped = b.appendingPathComponent(id.uuidString + ".jpg")
        try Data("before".utf8).write(to: original)
        try Data("stamped".utf8).write(to: stamped)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: owner, originalExtension: "jpg")
        try queue.markReady(id: id, original: original, processed: stamped)
        try Data("modified".utf8).write(to: original)
        let mock = PairTransportMock()
        let coordinator = CloudPairUploadCoordinator(queue: queue, root: root, accountIsCurrent: { $0 == owner }) {
            _, receipt, _, _, _ in await mock.upload(receipt)
        }
        let result = await coordinator.send(id: id, owner: owner, personalConsent: true,
                                            originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(result, .unavailable)
        let calls = await mock.received()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(try queue.entries(for: owner).first?.phase, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
    }

    func testKnownReceiptsResumeWithoutCreatingDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), owner = "person-a"
        let a = root.appendingPathComponent("Originals"), b = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let original = a.appendingPathComponent(id.uuidString + ".jpg")
        let stamped = b.appendingPathComponent(id.uuidString + ".jpg")
        try Data([0xff, 0xd8, 0xff, 0xd9, 0x01]).write(to: original)
        try Data([0xff, 0xd8, 0xff, 0xd9, 0x02]).write(to: stamped)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: owner, originalExtension: "jpg")
        try queue.markReady(id: id, original: original, processed: stamped)
        let transport = PairReceiptTransport()
        let uploader = PersonalPhotoUploader(directory: root.appendingPathComponent("Receipts"), transport: transport,
                                              accountIsCurrent: { $0 == owner })
        let coordinator = CloudPairUploadCoordinator(queue: queue, root: root, accountIsCurrent: { $0 == owner }) {
            bytes, receipt, user, filename, format in
            await uploader.upload(jpeg: bytes, captureID: receipt, owner: user,
                                  personalConsent: true, filename: filename, format: format)
        }
        let first = await coordinator.send(id: id, owner: owner, personalConsent: true,
                                           originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(first, .pending)
        await transport.allowVerification()
        let second = await coordinator.send(id: id, owner: owner, personalConsent: true,
                                            originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(second, .verified(original: "media-1", stamped: "media-2"))
        let creations = await transport.creationCount()
        XCTAssertEqual(creations, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
    }

    func testEndToEndPairKeepsFilesUntilBothAreVerifiedAndPreviewExists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), owner = "person-a"
        let a = root.appendingPathComponent("Originals"), b = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let original = a.appendingPathComponent(id.uuidString + ".jpg")
        let stamped = b.appendingPathComponent(id.uuidString + ".jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40))
        let photo = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
        let bytes = try XCTUnwrap(photo.jpegData(compressionQuality: 0.9))
        try bytes.write(to: original)
        try bytes.write(to: stamped)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try CloudCaptureStager.stage(root: root, captureID: id, ownerHash: CloudCaptureQueue.ownerHash(owner),
                                     originalExtension: "jpg")
        let transport = PairReceiptTransport()
        let uploader = PersonalPhotoUploader(directory: root.appendingPathComponent("Receipts"), transport: transport,
                                              accountIsCurrent: { $0 == owner })
        let coordinator = CloudPairUploadCoordinator(queue: queue, root: root, accountIsCurrent: { $0 == owner }) {
            data, receipt, user, filename, format in
            await uploader.upload(jpeg: data, captureID: receipt, owner: user, personalConsent: true,
                                  filename: filename, format: format)
        }
        let pending = await coordinator.send(id: id, owner: owner, personalConsent: true,
                                            originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(pending, .pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
        await transport.allowVerification()
        let complete = await coordinator.send(id: id, owner: owner, personalConsent: true,
                                             originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(complete, .verified(original: "media-1", stamped: "media-2"))
        let cleanup = CloudCaptureCleanup(queue: queue, root: root, accountIsCurrent: { $0 == owner }) { mediaID in
            (try? await transport.verifyItem(id: mediaID)) == true
        }
        let disabled = await cleanup.clean(id: id, owner: owner, cloudOnlyEnabled: false)
        XCTAssertEqual(disabled, .retained)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        let cleaned = await cleanup.clean(id: id, owner: owner, cloudOnlyEnabled: true)
        XCTAssertEqual(cleaned, .cleaned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stamped.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("CloudThumbnails")
            .appendingPathComponent(id.uuidString + ".jpg").path))
        XCTAssertEqual(try queue.entry(id: id).phase, .cleaned)
        let creations = await transport.creationCount()
        XCTAssertEqual(creations, 2)
    }

    func testAmbiguousUploadKeepsBothFilesAndDoesNotMarkVerified() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), owner = "person-a"
        let a = root.appendingPathComponent("Originals"), b = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let original = a.appendingPathComponent(id.uuidString + ".jpg")
        let stamped = b.appendingPathComponent(id.uuidString + ".jpg")
        try Data("original".utf8).write(to: original)
        try Data("stamped".utf8).write(to: stamped)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: owner, originalExtension: "jpg")
        try queue.markReady(id: id, original: original, processed: stamped)
        let coordinator = CloudPairUploadCoordinator(queue: queue, root: root, accountIsCurrent: { $0 == owner }) {
            _, _, _, _, _ in .uncertain
        }
        let result = await coordinator.send(id: id, owner: owner, personalConsent: true,
                                            originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        XCTAssertEqual(result, .uncertain)
        XCTAssertEqual(try queue.entry(id: id).phase, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
    }

    func testCancelledBackgroundPassRetainsFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), owner = "person-a"
        let originals = root.appendingPathComponent("Originals"), processed = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        let original = originals.appendingPathComponent(id.uuidString + ".jpg")
        let stamped = processed.appendingPathComponent(id.uuidString + ".jpg")
        try Data("original".utf8).write(to: original)
        try Data("stamped".utf8).write(to: stamped)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        try queue.enqueue(id: id, owner: owner, originalExtension: "jpg")
        try queue.markReady(id: id, original: original, processed: stamped)
        let transport = SuspendedPairTransport()
        let coordinator = CloudPairUploadCoordinator(queue: queue, root: root,
            accountIsCurrent: { _ in !Task.isCancelled }) { _, _, _, _, _ in await transport.upload() }
        let work = Task {
            await coordinator.send(id: id, owner: owner, personalConsent: true,
                                   originalFilename: "original.jpg", stampedFilename: "stamped.jpg")
        }
        for _ in 0..<200 {
            if await transport.started() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await transport.started()
        guard started else { work.cancel(); XCTFail("O envio não começou"); return }
        work.cancel()
        await transport.finish()
        let result = await work.value
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(try queue.entry(id: id).phase, .ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.path))
    }

}
