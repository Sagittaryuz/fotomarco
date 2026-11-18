import XCTest
@testable import Momentra

final class RecognitionWebURLTests: XCTestCase {
    func testOnlyWebAddressesOpenAsLinks() {
        XCTAssertEqual(RecognitionWebURL.parse("https://example.com/path")?.host, "example.com")
        XCTAssertEqual(RecognitionWebURL.parse("www.example.com")?.scheme, "https")
        XCTAssertNil(RecognitionWebURL.parse("javascript:alert(1)"))
        XCTAssertNil(RecognitionWebURL.parse("mailto:test@example.com"))
        XCTAssertNil(RecognitionWebURL.parse("https://user:password@example.com"))
        XCTAssertNil(RecognitionWebURL.parse("texto detectado"))
    }
}
