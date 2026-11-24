import XCTest
@testable import Momentra

final class BusinessLegacyCloudStageTests: XCTestCase {
    func testStagesBothVersionsWithoutChangingSourceFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stamped = root.appendingPathComponent("source.jpg"), original = root.appendingPathComponent("source.heic")
        try Data([1, 2]).write(to: stamped); try Data([3, 4]).write(to: original)
        let id = UUID(), org = UUID(), date = Date(timeIntervalSince1970: 100)
        try BusinessLegacyCloudStage.stage(root: root, stamped: stamped, original: original, captureID: id, date: date,
                                          organizationID: org, userID: "owner", cutoff: Date(timeIntervalSince1970: 200))
        let journal = BusinessArchiveJournal(root: root), item = try journal.read(id)
        XCTAssertTrue(item.ready); XCTAssertTrue(item.keepsOriginal)
        XCTAssertEqual(try Data(contentsOf: stamped), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: original), Data([3, 4]))
        XCTAssertEqual(try Data(contentsOf: journal.stampedURL(item)), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: journal.originalURL(item)), Data([3, 4]))
    }

    func testRejectsNewerOrDifferentOrganizationCapture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.jpg"), id = UUID(), org = UUID()
        try Data([1]).write(to: source)
        XCTAssertThrowsError(try BusinessLegacyCloudStage.stage(root: root, stamped: source, original: nil, captureID: id,
            date: Date(timeIntervalSince1970: 300), organizationID: org, userID: "owner", cutoff: Date(timeIntervalSince1970: 200)))
        try PhotoProfileIndex.register(captureID: id, profile: .init(id: UUID(), name: "Outro"), captureDate: Date(timeIntervalSince1970: 100), root: root)
        XCTAssertThrowsError(try BusinessLegacyCloudStage.stage(root: root, stamped: source, original: nil, captureID: id,
            date: Date(timeIntervalSince1970: 100), organizationID: org, userID: "owner", cutoff: Date(timeIntervalSince1970: 200)))
        XCTAssertTrue(try BusinessArchiveJournal(root: root).ids().isEmpty)
    }
}
