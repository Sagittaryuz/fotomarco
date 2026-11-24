import XCTest
@testable import Momentra

final class BusinessArchiveJournalTests: XCTestCase {
    func testTeamCaptureUsesDurableCopiesAndFrozenIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.heic")
        let stamped = root.appendingPathComponent("stamped.jpg")
        try Data([1, 2, 3]).write(to: source)
        try Data([4, 5, 6, 7]).write(to: stamped)
        let id = UUID(), organization = UUID(), date = Date(timeIntervalSince1970: 1_795_470_002)
        let target = BusinessCaptureTarget(organizationID: organization, userID: "member-uid", keepsOriginal: true)
        let profile = CaptureProfileTag(id: organization, name: "Equipe")
        let journal = BusinessArchiveJournal(root: root)
        try journal.enqueue(id: id, date: date, originalExtension: "heic", source: source, target: target, profile: profile)
        var capture = try journal.read(id)
        XCTAssertFalse(capture.ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.originalURL(capture).path))
        XCTAssertTrue(capture.originalName.contains("OneDrive"))
        XCTAssertEqual(CloudArchiveFilename(capture.stampedName)?.profile?.id, organization)
        try journal.markReady(id: id, stampedSource: stamped)
        capture = try journal.read(id)
        XCTAssertTrue(capture.ready)
        XCTAssertFalse(capture.finished)
        try journal.markVerified(id, variant: "original")
        XCTAssertFalse(try journal.read(id).finished)
        try journal.markVerified(id, variant: "stamped")
        capture = try BusinessArchiveJournal(root: root).read(id)
        XCTAssertTrue(capture.finished)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.stampedURL(capture).path))
        XCTAssertThrowsError(try journal.enqueue(id: id, date: date, originalExtension: "heic", source: source,
            target: BusinessCaptureTarget(organizationID: organization, userID: "other", keepsOriginal: true), profile: profile))
    }
}
