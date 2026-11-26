import XCTest
@testable import Momentra

final class CloudArchiveJournalTests: XCTestCase {
    func testBusinessDedupJournalCannotDisableLocalRetention() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = CloudArchiveJournal(root: root)
        let id = UUID()
        let destination = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: String(repeating: "a", count: 64)))
        let context = CloudDeliveryPlan.OrganizationDedup(organizationID: UUID(), userID: "user-A")
        let plan = try XCTUnwrap(CloudDeliveryPlan(keepLocal: true, destinations: [destination], organizationDedup: context))
        try journal.enqueue(id: id, date: Date(), originalExtension: "jpg", plan: plan)
        let encoded = try JSONEncoder().encode(journal.read(id))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var modifiedPlan = try XCTUnwrap(object["plan"] as? [String: Any])
        modifiedPlan["keepLocal"] = false
        object["plan"] = modifiedPlan
        let corrupted = try JSONDecoder().decode(CloudArchiveJournal.Capture.self, from: JSONSerialization.data(withJSONObject: object))
        try journal.write(corrupted)
        XCTAssertThrowsError(try journal.read(id))
    }
    func testRenamedArchivePreservesIdentityAndIsIdempotent() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1234)
        let profile = CaptureProfileTag(id: UUID(), name: "Equipe")
        let old = CloudArchiveFilename.make(captureID: id, capturedAt: date, profile: profile, originalExtension: nil)
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        for (provider, label) in [(CloudDeliveryPlan.Provider.oneDrive, "OneDrive"), (.googleDrive, "Google Drive")] {
            let renamed = try XCTUnwrap(CloudArchiveFilename.renamed(old, provider: provider, timeZone: zone))
            XCTAssertTrue(renamed.hasPrefix("01-01-1970 - \(label) - 00-20-34 - "))
            let decoded = try XCTUnwrap(CloudArchiveFilename(renamed))
            XCTAssertEqual(decoded.captureID, id)
            XCTAssertEqual(decoded.capturedAt, date)
            XCTAssertEqual(decoded.profile, profile)
            XCTAssertEqual(CloudArchiveFilename.renamed(renamed, provider: provider, timeZone: zone), renamed)
        }
        XCTAssertNil(CloudArchiveFilename.renamed("\(id.uuidString)-stamped.jpg", provider: .oneDrive, timeZone: zone))
        let oldWithoutDate = "\(id.uuidString)-stamped.jpg"
        let fromProvider = try XCTUnwrap(CloudArchiveFilename.renamed(oldWithoutDate, provider: .oneDrive, timeZone: zone,
                                                                      knownCaptureDate: date))
        XCTAssertTrue(fromProvider.hasPrefix("01-01-1970 - OneDrive - 00-20-34 - "))
        XCTAssertEqual(CloudArchiveFilename(fromProvider)?.captureID, id)
        XCTAssertEqual(CloudArchiveFilename(fromProvider)?.capturedAt, date)
    }

    func testArchiveNameCarriesCaptureDateAndProfileAcrossDevices() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let profile = CaptureProfileTag(id: UUID(), name: "Medição · Fundação")
        let name = CloudArchiveFilename.make(captureID: id, capturedAt: date, profile: profile, originalExtension: "heic")
        let decoded = try XCTUnwrap(CloudArchiveFilename(name))
        XCTAssertEqual(decoded.captureID, id)
        XCTAssertEqual(decoded.capturedAt, date)
        XCTAssertEqual(decoded.profile, profile)
        XCTAssertTrue(decoded.isOriginal)
        XCTAssertLessThanOrEqual(name.utf8.count, 160)
        XCTAssertNil(CloudArchiveFilename("\(id.uuidString)-original.jpg.exe"))
        XCTAssertNil(CloudArchiveFilename("\(id.uuidString)-stamped.heic"))
        XCTAssertNil(CloudArchiveFilename("\(id.uuidString).nan-stamped.jpg"))
        XCTAssertNotNil(CloudArchiveFilename("\(id.uuidString)-stamped.jpg"))
    }

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
        XCTAssertTrue(reopened.remoteName(stamped: true, destination: google).contains(" - Google Drive - "))
        XCTAssertTrue(reopened.remoteName(stamped: true, destination: microsoft).contains(" - OneDrive - "))
        XCTAssertEqual(reopened.remoteName(stamped: true, destination: google), item.remoteName(stamped: true, destination: google))
        XCTAssertEqual(reopened.plan.deliveries.map(\.destination), [google, microsoft])
        XCTAssertEqual(reopened.plan.deliveries.map(\.phase), [.verified, .pending])
        XCTAssertFalse(reopened.plan.destinationsVerified)
        let changed = try XCTUnwrap(CloudDeliveryPlan(keepLocal: true, destinations: [microsoft]))
        XCTAssertThrowsError(try journal.enqueue(id: id, date: date, originalExtension: "heic", plan: changed))

        // Journals made by an older version retain their original destination names.
        item.providerNames = nil
        try journal.write(item)
        let legacy = try journal.read(id)
        XCTAssertEqual(legacy.remoteName(stamped: true, destination: google), legacy.remoteName(stamped: true))
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
