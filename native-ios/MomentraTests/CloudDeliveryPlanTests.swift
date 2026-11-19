import XCTest
@testable import Momentra

final class CloudDeliveryPlanTests: XCTestCase {
    private let google = CloudDeliveryPlan.Destination(provider: .googleDrive, accountHash: String(repeating: "a", count: 64))!
    private let microsoft = CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: String(repeating: "b", count: 64))!

    func testAllDestinationsMustConfirmBothVersions() throws {
        var plan = try XCTUnwrap(CloudDeliveryPlan(keepLocal: false, destinations: [google, microsoft]))
        plan.confirm(destination: google, originalID: "original", stampedID: "stamped")
        XCTAssertFalse(plan.destinationsVerified)
        plan.confirm(destination: microsoft, originalID: "original", stampedID: "")
        XCTAssertFalse(plan.destinationsVerified)
        plan.confirm(destination: microsoft, originalID: "original", stampedID: "stamped")
        XCTAssertTrue(plan.destinationsVerified)
        XCTAssertEqual(try JSONDecoder().decode(CloudDeliveryPlan.self, from: JSONEncoder().encode(plan)), plan)
    }

    func testUncertainDeliveryCannotBeImplicitlyConfirmed() throws {
        var plan = try XCTUnwrap(CloudDeliveryPlan(keepLocal: false, destinations: [google]))
        plan.markUncertain(destination: google)
        plan.confirm(destination: google, originalID: "original", stampedID: "stamped")
        XCTAssertFalse(plan.destinationsVerified)
        XCTAssertEqual(plan.deliveries.first?.phase, .uncertain)
    }

    func testProcessedOnlyPlanRequiresOnlyTheProcessedReceipt() throws {
        var plan = try XCTUnwrap(CloudDeliveryPlan(keepLocal: false, destinations: [google, microsoft], keepOriginal: false))
        plan.confirm(destination: google, originalID: "unexpected", stampedID: "processed-google")
        XCTAssertEqual(plan.deliveries.first?.phase, .pending)
        plan.confirm(destination: google, originalID: nil, stampedID: "processed-google")
        XCTAssertFalse(plan.destinationsVerified)
        plan.confirm(destination: microsoft, originalID: nil, stampedID: "processed-microsoft")
        XCTAssertTrue(plan.destinationsVerified)
        XCTAssertFalse(try JSONDecoder().decode(CloudDeliveryPlan.self, from: JSONEncoder().encode(plan)).keepsOriginal)
    }

    func testOlderPlanWithoutAnOriginalPreferenceStillRequiresBothVersions() throws {
        var plan = try XCTUnwrap(CloudDeliveryPlan(keepLocal: true, destinations: [google]))
        let bytes = try JSONEncoder().encode(plan)
        XCTAssertNil((try JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["keepOriginal"])
        plan = try JSONDecoder().decode(CloudDeliveryPlan.self, from: bytes)
        plan.confirm(destination: google, originalID: nil, stampedID: "processed")
        XCTAssertTrue(plan.keepsOriginal)
        XCTAssertFalse(plan.destinationsVerified)
    }

    func testRejectsMissingOrDuplicateDestinations() {
        XCTAssertNil(CloudDeliveryPlan(keepLocal: false, destinations: []))
        XCTAssertNil(CloudDeliveryPlan(keepLocal: true, destinations: [google, google]))
        XCTAssertNotNil(CloudDeliveryPlan(keepLocal: true, destinations: []))
        XCTAssertNil(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: "email@example.com"))
    }

    func testCorruptedPersistedReceiptCannotBeVerified() throws {
        let plan = try XCTUnwrap(CloudDeliveryPlan(keepLocal: false, destinations: [google]))
        let encoded = try JSONEncoder().encode(plan)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var deliveries = try XCTUnwrap(object["deliveries"] as? [[String: Any]])
        deliveries[0]["phase"] = "verified"
        object["deliveries"] = deliveries
        let corrupted = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(try JSONDecoder().decode(CloudDeliveryPlan.self, from: corrupted).destinationsVerified)
    }
}
