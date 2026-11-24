import XCTest
@testable import Momentra

final class BusinessLegacyLocalImportTests: XCTestCase {
    func testStagesHistoricalCopiesWithoutChangingSourceAndRespectsLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let processed = root.appendingPathComponent("Processed"), originals = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let organization = UUID(), ids = [UUID(), UUID()], date = Date(timeIntervalSince1970: 100)
        let image = Data([1, 2, 3]), original = Data([4, 5, 6])
        for id in ids {
            try image.write(to: processed.appendingPathComponent(id.uuidString + ".jpg"))
            try original.write(to: originals.appendingPathComponent(id.uuidString + ".heic"))
            try PhotoProfileIndex.register(captureID: id, profile: .init(id: UUID(), name: "Antigo"), captureDate: date, root: root)
        }
        _ = try PhotoProfileIndex.associateLegacyCaptures(organizationID: organization, name: "JMD Hamoa", before: Date(timeIntervalSince1970: 200), root: root)
        let first = try BusinessLegacyLocalImport.stage(root: root, organizationID: organization, userID: "owner", cutoff: Date(timeIntervalSince1970: 200), limit: 1)
        XCTAssertEqual(first.staged, 1); XCTAssertTrue(first.more)
        let second = try BusinessLegacyLocalImport.stage(root: root, organizationID: organization, userID: "owner", cutoff: Date(timeIntervalSince1970: 200), limit: 1)
        XCTAssertEqual(second.staged, 1)
        let journal = BusinessArchiveJournal(root: root)
        XCTAssertEqual(try journal.ids().count, 2)
        for id in ids {
            XCTAssertEqual(try Data(contentsOf: processed.appendingPathComponent(id.uuidString + ".jpg")), image)
            XCTAssertEqual(try Data(contentsOf: originals.appendingPathComponent(id.uuidString + ".heic")), original)
            let capture = try journal.read(id)
            XCTAssertTrue(capture.ready); XCTAssertTrue(capture.keepsOriginal)
            XCTAssertEqual(try Data(contentsOf: journal.stampedURL(capture)), image)
            XCTAssertEqual(try Data(contentsOf: journal.originalURL(capture)), original)
        }
    }

    func testSkipsUnindexedAndNewerPhotos() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let processed = root.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        let newer = UUID(), unindexed = UUID(), organization = UUID()
        for id in [newer, unindexed] { try Data([1]).write(to: processed.appendingPathComponent(id.uuidString + ".jpg")) }
        try PhotoProfileIndex.register(captureID: newer, profile: .init(id: organization, name: "JMD Hamoa"),
                                       captureDate: Date(timeIntervalSince1970: 300), root: root)
        let result = try BusinessLegacyLocalImport.stage(root: root, organizationID: organization, userID: "owner", cutoff: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(result.staged, 0); XCTAssertEqual(result.unresolved, 1)
        XCTAssertTrue(try BusinessArchiveJournal(root: root).ids().isEmpty)
    }

    func testResumesStagingAfterAnInterruptedCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let processed = root.appendingPathComponent("Processed"), id = UUID(), organization = UUID(), date = Date(timeIntervalSince1970: 100)
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        let source = processed.appendingPathComponent(id.uuidString + ".jpg")
        try Data([1, 2, 3]).write(to: source)
        try PhotoProfileIndex.register(captureID: id, profile: .init(id: organization, name: "JMD Hamoa"), captureDate: date, root: root)
        let journal = BusinessArchiveJournal(root: root)
        try journal.enqueue(id: id, date: date, originalExtension: "jpg", source: source,
            target: .init(organizationID: organization, userID: "owner", keepsOriginal: false),
            profile: .init(id: organization, name: "JMD Hamoa"))
        XCTAssertFalse(try journal.read(id).ready)
        let result = try BusinessLegacyLocalImport.stage(root: root, organizationID: organization, userID: "owner", cutoff: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(result.staged, 1)
        XCTAssertTrue(try journal.read(id).ready)
    }
}
