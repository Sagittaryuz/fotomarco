import XCTest
@testable import Momentra

final class CloudArchiveJournalTests: XCTestCase {
    func testReopeningPreservesTheFrozenDestinationsAndVerifiedReceipts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = CloudArchiveJournal(root: root)
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1234)
        let google = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .googleDrive, accountHash: String(repeating: "1", count: 64)))
        let microsoft = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: String(repeating: "2", count: 64)))
        let plan = try XCTUnwrap(CloudDeliveryPlan(keepLocal: false, destinations: [google, microsoft]))

        try journal.enqueue(id: id, date: date, originalExtension: "heic", plan: plan)
        var item = try journal.read(id)
        item.plan.confirm(destination: google, originalID: "a", stampedID: "b")
        try journal.write(item)
        try journal.enqueue(id: id, date: date, originalExtension: "heic", plan: plan)

        let reopened = try CloudArchiveJournal(root: root).read(id)
        XCTAssertEqual(reopened.plan.deliveries.map(\.destination), [google, microsoft])
        XCTAssertEqual(reopened.plan.deliveries.map(\.phase), [.verified, .pending])
        XCTAssertFalse(reopened.plan.destinationsVerified)
        let changed = try XCTUnwrap(CloudDeliveryPlan(keepLocal: true, destinations: [microsoft]))
        XCTAssertThrowsError(try journal.enqueue(id: id, date: date, originalExtension: "heic", plan: changed))
    }

    func testMarkReadyRequiresTwoCompleteFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = CloudArchiveJournal(root: root)
        let id = UUID()
        let destination = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: String(repeating: "a", count: 64)))
        let plan = try XCTUnwrap(CloudDeliveryPlan(keepLocal: false, destinations: [destination]))
        try journal.enqueue(id: id, date: Date(), originalExtension: "jpg", plan: plan)
        let item = try journal.read(id)
        let original = journal.file(item, stamped: false)
        let stamped = journal.file(item, stamped: true)
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: original)

        XCTAssertThrowsError(try journal.markReady(id: id))
        XCTAssertNil(try journal.read(id).original)
        try FileManager.default.createDirectory(at: stamped.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([4, 5]).write(to: stamped)
        try journal.markReady(id: id)
        XCTAssertEqual(try journal.read(id).original?.byteCount, 3)
        XCTAssertEqual(try journal.read(id).stamped?.byteCount, 2)
    }
}
