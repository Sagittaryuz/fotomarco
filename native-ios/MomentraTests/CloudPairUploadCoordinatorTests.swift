import XCTest
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
}
