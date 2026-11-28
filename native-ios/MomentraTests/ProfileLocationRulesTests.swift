import XCTest
import CoreLocation
@testable import Momentra

@MainActor
final class ProfileLocationRulesTests: XCTestCase {
    private func location(_ latitude: Double, _ longitude: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: longitude), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: .now)
    }
    func testMultipleAreasAndFallback() throws {
        let suite = "ProfileLocationRulesTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rules = ProfileLocationRules(defaults: defaults)
        let personal = UUID(), organization = UUID()
        let a = ProfileArea(profileID: organization, name: "Obra 1", latitude: -17.88, longitude: -51.72, radius: 200)
        let b = ProfileArea(profileID: organization, name: "Obra 2", latitude: -17.90, longitude: -51.74, radius: 150)
        rules.save(organization, areas: [a, b], fallback: personal)
        XCTAssertEqual(rules.areas(for: organization).count, 2)
        XCTAssertEqual(rules.selection(for: location(-17.90, -51.74), available: [personal, organization], current: personal), organization)
        XCTAssertEqual(rules.selection(for: location(-18.00, -51.80), available: [personal, organization], current: organization), personal)
    }
    func testManualSelectionRemainsUntilLeavingArea() throws {
        let suite = "ProfileLocationRulesTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rules = ProfileLocationRules(defaults: defaults)
        let personal = UUID(), work = UUID()
        let area = ProfileArea(profileID: work, name: "Obra", latitude: -17.88, longitude: -51.72, radius: 200)
        rules.save(work, areas: [area], fallback: nil)
        XCTAssertEqual(rules.selection(for: location(-17.88, -51.72), available: [personal, work], current: personal), work)
        rules.manualSelection()
        XCTAssertNil(rules.selection(for: location(-17.88, -51.72), available: [personal, work], current: personal))
        XCTAssertNil(rules.selection(for: location(-18, -52), available: [personal, work], current: personal))
        XCTAssertEqual(rules.selection(for: location(-17.88, -51.72), available: [personal, work], current: personal), work)
    }
    func testInaccuratePositionDoesNotChangeProfile() throws {
        let suite = "ProfileLocationRulesTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rules = ProfileLocationRules(defaults: defaults)
        let personal = UUID(), work = UUID()
        rules.save(work, areas: [.init(profileID: work, name: "Obra", latitude: -17.88, longitude: -51.72, radius: 200)], fallback: personal)
        XCTAssertNil(rules.selection(for: location(-17.88, -51.72, accuracy: 150), available: [personal, work], current: personal))
    }
}
