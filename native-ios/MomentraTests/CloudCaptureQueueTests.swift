import XCTest
@testable import Momentra

final class CloudCaptureQueueTests: XCTestCase {
    func testQueuePersistsAndSeparatesAccounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let queue = CloudCaptureQueue(directory: root)
        try queue.enqueue(id: id, owner: "account-a", originalExtension: "HEIC")
        try queue.markReady(id: id)
        let restored = CloudCaptureQueue(directory: root)
        XCTAssertEqual(try restored.entries(for: "account-a").first?.phase, .ready)
        XCTAssertTrue(try restored.entries(for: "account-b").isEmpty)
        XCTAssertEqual(try restored.entries(for: "account-a").first?.originalExtension, "heic")
    }

    func testOnlyTwoConfirmedRemoteItemsCanMarkVerified() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let queue = CloudCaptureQueue(directory: root)
        try queue.enqueue(id: id, owner: "account", originalExtension: "jpg")
        XCTAssertThrowsError(try queue.markVerified(id: id, originalMediaID: "a", processedMediaID: "b"))
        try queue.markReady(id: id)
        XCTAssertThrowsError(try queue.markVerified(id: id, originalMediaID: "", processedMediaID: "b"))
        try queue.markVerified(id: id, originalMediaID: "a", processedMediaID: "b")
        XCTAssertEqual(try queue.entries(for: "account").first?.phase, .verified)
        XCTAssertThrowsError(try queue.markReady(id: id))
    }

    func testUncertainUploadCannotBeDeclaredVerified() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let queue = CloudCaptureQueue(directory: root)
        try queue.enqueue(id: id, owner: "account", originalExtension: "heic")
        try queue.markReady(id: id)
        try queue.markUncertain(id: id)
        XCTAssertThrowsError(try queue.markVerified(id: id, originalMediaID: "a", processedMediaID: "b"))
        XCTAssertEqual(try queue.entries(for: "account").first?.phase, .uncertain)
    }
}
