import XCTest
@testable import Momentra

@MainActor
final class NativeGoogleAuthTests: XCTestCase {
    func testRequiresAnIOSClientAndMatchingRedirectScheme() {
        let id = "123456-example.apps.googleusercontent.com"
        let scheme = "com.googleusercontent.apps.123456-example"
        XCTAssertFalse(NativeGoogleAuth.validConfiguration([:]))
        XCTAssertFalse(NativeGoogleAuth.validConfiguration(["GIDClientID": id]))
        XCTAssertFalse(NativeGoogleAuth.validConfiguration(["GIDClientID": id, "CFBundleURLTypes": [["CFBundleURLSchemes": ["unrelated"]]]]))
        XCTAssertTrue(NativeGoogleAuth.validConfiguration(["GIDClientID": id, "CFBundleURLTypes": [["CFBundleURLSchemes": [scheme]]]]))
    }
}
