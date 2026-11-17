import XCTest
@testable import Momentra

final class UpdateVersionTests: XCTestCase {
    func testNumericComparison() throws {
        XCTAssertGreaterThan(try XCTUnwrap(UpdateVersion("1.10.0")), try XCTUnwrap(UpdateVersion("1.9.9")))
        XCTAssertNil(UpdateVersion("1.2"))
        XCTAssertNil(UpdateVersion("1.2.3-beta"))
    }

    func testOnlyPublishedNativeTagsAreAccepted() {
        XCTAssertNotNil(UpdateRelease(tag_name: "native-ios-v1.2.3", draft: false, prerelease: false).version)
        XCTAssertNil(UpdateRelease(tag_name: "native-ios-v1.2.3", draft: true, prerelease: false).version)
        XCTAssertNil(UpdateRelease(tag_name: "native-ios-v1.2.3", draft: false, prerelease: true).version)
        XCTAssertNil(UpdateRelease(tag_name: "scripting-v1.2.3", draft: false, prerelease: false).version)
    }
}
