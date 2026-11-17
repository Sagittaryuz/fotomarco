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

    func testForegroundChecksAreThrottledButManualChecksAreAllowed() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(lastAttempt: nil, now: now, force: false))
        XCTAssertFalse(UpdateCheckPolicy.shouldCheck(lastAttempt: now.addingTimeInterval(-60), now: now, force: false))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(lastAttempt: now.addingTimeInterval(-3600), now: now, force: false))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(lastAttempt: now, now: now, force: true))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheck(lastAttempt: now.addingTimeInterval(60), now: now, force: false))
    }
}
