import XCTest
@testable import Momentra

final class ReleaseNewsTests: XCTestCase {
    func testNewsBelongsToCurrentVersionOnly() {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(current, ReleaseNews.version, "Atualize as novidades para a versão antes de publicar.")
        XCTAssertFalse(ReleaseNews.items(for: ReleaseNews.version).isEmpty)
        XCTAssertTrue(ReleaseNews.items(for: "0.1.39").isEmpty)
    }
}
