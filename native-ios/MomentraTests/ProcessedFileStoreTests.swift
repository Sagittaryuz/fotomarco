import XCTest
@testable import Momentra

final class ProcessedFileStoreTests: XCTestCase {
    func testProcessedFilesArePersistedWithoutOverwriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = Data([1, 2, 3])
        let second = Data([4, 5, 6])
        let firstURL = try ProcessedFileStore.save(first, root: root)
        let secondURL = try ProcessedFileStore.save(second, root: root)
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try Data(contentsOf: firstURL), first)
        XCTAssertEqual(try Data(contentsOf: secondURL), second)
        XCTAssertThrowsError(try ProcessedFileStore.save(Data(), root: root))
    }
}
