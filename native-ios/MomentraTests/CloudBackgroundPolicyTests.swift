import XCTest
@testable import Momentra

final class CloudBackgroundPolicyTests: XCTestCase {
    func testOnlyActionablePhasesNeedScheduling() {
        XCTAssertFalse(CloudBackgroundPolicy.shouldSchedule([]))
        XCTAssertFalse(CloudBackgroundPolicy.shouldSchedule([.uncertain, .cleaned]))
        XCTAssertTrue(CloudBackgroundPolicy.shouldSchedule([.ready]))
        XCTAssertTrue(CloudBackgroundPolicy.shouldSchedule([.verified]))
        XCTAssertTrue(CloudBackgroundPolicy.shouldSchedule([.cleaning]))
        XCTAssertTrue(CloudBackgroundPolicy.shouldSchedule([.awaitingPhoto]))
    }

    func testBackgroundIdentifiersAreInAppBundle() {
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        XCTAssertTrue(identifiers?.contains(CloudBackgroundScheduler.identifier) == true)
        XCTAssertTrue(modes?.contains("processing") == true)
    }
}
