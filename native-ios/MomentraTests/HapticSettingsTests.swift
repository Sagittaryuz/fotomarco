import XCTest
@testable import Momentra

final class HapticSettingsTests: XCTestCase {
    func testDefaultsAreIndependentAndCanBeDisabled() throws {
        let suite = "haptics-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(FotomarcoHaptics.intensity(.photo, defaults: defaults), 0.2, accuracy: 0.001)
        XCTAssertEqual(FotomarcoHaptics.intensity(.quickShare, defaults: defaults), 0.4, accuracy: 0.001)
        defaults.set(0.0, forKey: HapticEvent.photo.storageKey)
        XCTAssertEqual(FotomarcoHaptics.intensity(.photo, defaults: defaults), 0)
        XCTAssertEqual(FotomarcoHaptics.intensity(.zoom, defaults: defaults), 0.2, accuracy: 0.001)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(FotomarcoHaptics.intensity(.photo, defaults: reopened), 0)
    }

    func testStoredValuesStayWithinSupportedRange() throws {
        let suite = "haptics-range-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(-1, forKey: HapticEvent.zoom.storageKey)
        XCTAssertEqual(FotomarcoHaptics.intensity(.zoom, defaults: defaults), 0)
        defaults.set(2, forKey: HapticEvent.zoom.storageKey)
        XCTAssertEqual(FotomarcoHaptics.intensity(.zoom, defaults: defaults), 1)
    }
}
