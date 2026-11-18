import XCTest
import CoreLocation
@testable import Momentra

@MainActor
final class StampProfilesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "momentra.tests.stamp." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testMigrationCreatesOneNamedProfileAndRetainsLegacyKeys() {
        defaults.set("PIRESCO", forKey: "native.profile")
        defaults.set("Nota existente", forKey: "native.profile.piresco.note")
        defaults.set("old-logo.png", forKey: "native.profile.piresco.logo")
        let store = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.selected.name, "Padrão")
        XCTAssertEqual(store.selected.note, "Nota existente")
        XCTAssertEqual(store.selected.logoName, "old-logo.png")
        XCTAssertEqual(defaults.string(forKey: "native.profile.piresco.logo"), "old-logo.png")
    }

    func testFiveProfilesPersistAndSixthIsRejected() {
        let store = StampProfilesStore(defaults: defaults)
        for _ in 0..<4 { XCTAssertTrue(store.create()) }
        XCTAssertFalse(store.create())
        XCTAssertEqual(store.profiles.count, 5)
        store.rename("Projeto")
        let restored = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(restored.profiles.count, 5)
        XCTAssertEqual(restored.selected.name, "Projeto")
    }

    func testRemovingSelectedProfileKeepsAtLeastOne() {
        let store = StampProfilesStore(defaults: defaults)
        store.removeSelected()
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertTrue(store.create())
        store.removeSelected()
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.selected.name, "Padrão")
    }

    func testNormalizedPositionIsBoundedAndClampedIntoPhoto() {
        let point = StampPoint(x: -1, y: 2)
        XCTAssertEqual(point, StampPoint(x: 0, y: 1))
        let bounds = CGSize(width: 1000, height: 1500)
        let rect = StampRenderer.positionedRect(size: bounds, element: CGSize(width: 200, height: 200), centre: point, margin: 20)
        XCTAssertEqual(rect.minX, 20)
        XCTAssertEqual(rect.maxY, 1480)
    }
}
