import XCTest
@testable import Momentra

final class CloudStoragePreferenceTests: XCTestCase {
    func testPreferenceIsAccountBoundAndCanBeDisabled() throws {
        let name = "MomentraTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertNil(CloudStoragePreference.selectedHash(defaults: defaults))
        CloudStoragePreference.enable(owner: "person-a", defaults: defaults)
        XCTAssertTrue(CloudStoragePreference.enabled(for: "person-a", defaults: defaults))
        XCTAssertFalse(CloudStoragePreference.enabled(for: "person-b", defaults: defaults))
        XCTAssertNotEqual(defaults.string(forKey: CloudStoragePreference.key), "person-a")
        CloudStoragePreference.disable(defaults: defaults)
        XCTAssertFalse(CloudStoragePreference.enabled(for: "person-a", defaults: defaults))
    }
}
