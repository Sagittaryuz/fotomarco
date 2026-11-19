import XCTest
@testable import Momentra

final class GalleryCapacityCacheTests: XCTestCase {
    func testStorageReadingsPersistAndStayScopedToTheirAccounts() throws {
        let suite = "GalleryCapacityCacheTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let google = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .googleDrive, accountHash: String(repeating: "1", count: 64)))
        let oneDrive = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: google.accountHash))
        let first = GalleryCapacityCache(defaults: defaults)
        first.store(.init(total: 100, used: 31), for: google)
        first.store(.init(total: 200, used: 90), for: oneDrive)
        first.store(.init(total: 0, used: 0), for: google)
        first.store(try XCTUnwrap(StorageTotals(total: 128, used: 45, primary: 0)), includeAppBytes: false)

        let reopened = GalleryCapacityCache(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(reopened.quota(for: google)?.used, 31)
        XCTAssertEqual(reopened.quota(for: oneDrive)?.used, 90)
        XCTAssertEqual(reopened.local(includeAppBytes: false)?.used, 45)
        XCTAssertNil(reopened.local(includeAppBytes: true))
    }
}
