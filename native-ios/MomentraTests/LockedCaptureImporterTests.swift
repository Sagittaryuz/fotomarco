import XCTest
@testable import Momentra

@available(iOS 18.0, *)
final class LockedCaptureImporterTests: XCTestCase {
    func testImportIsIdempotentAndPreservesSourceAndExistingFiles() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = base.appendingPathComponent("session", isDirectory: true)
        let destination = base.appendingPathComponent("originals", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let name = UUID().uuidString + ".jpg"
        let data = Data([1, 2, 3])
        try data.write(to: source.appendingPathComponent(name))
        try Data([9]).write(to: source.appendingPathComponent("not-a-uuid.jpg"))
        LockedCaptureImporter.copyFiles(from: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(name)), data)
        XCTAssertTrue(fm.fileExists(atPath: source.appendingPathComponent(name).path))
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("not-a-uuid.jpg").path))
        try Data([7]).write(to: destination.appendingPathComponent(name))
        LockedCaptureImporter.copyFiles(from: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(name)), Data([7]))
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent(name)), data)
    }
}
