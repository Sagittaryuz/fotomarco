import XCTest
@testable import Momentra

final class CloudFileFingerprintTests: XCTestCase {
    func testFingerprintChangesWhenFullFileChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("photo.jpg")
        try Data("first".utf8).write(to: url)
        let first = try CloudFileFingerprint.read(url)
        try Data("other".utf8).write(to: url)
        let second = try CloudFileFingerprint.read(url)
        XCTAssertEqual(first.byteCount, second.byteCount)
        XCTAssertNotEqual(first.sha256, second.sha256)
    }

    func testRejectsSymbolicLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("photo.jpg")
        let link = root.appendingPathComponent("link.jpg")
        try Data("photo".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try CloudFileFingerprint.read(link))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
