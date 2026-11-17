import XCTest
@testable import Momentra

@MainActor
final class DirectUpdateAccessTests: XCTestCase {
    func testAcceptsOnlyExpectedActivationLink() {
        let token = String(repeating: "a", count: 64)
        XCTAssertEqual(DirectUpdateAccess.token(from: URL(string: "momentra://updates/activate?token=\(token)")!), token)
        XCTAssertNil(DirectUpdateAccess.token(from: URL(string: "momentra://other/activate?token=\(token)")!))
        XCTAssertNil(DirectUpdateAccess.token(from: URL(string: "https://updates/activate?token=\(token)")!))
        XCTAssertNil(DirectUpdateAccess.token(from: URL(string: "momentra://updates/activate?token=bad")!))
        XCTAssertNil(DirectUpdateAccess.token(from: URL(string: "momentra://updates/activate?token=\(token)&extra=1")!))
    }
}
