import XCTest
import SwiftUI
@testable import Momentra

@MainActor
final class CloudUploadProgressTests: XCTestCase {
    func testDestinationProgressIsIndependentAndRequiresVerification() throws {
        let tracker = CloudUploadProgress.shared
        let id = UUID()
        let google = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .googleDrive, accountHash: String(repeating: "a", count: 64)))
        let oneDrive = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: String(repeating: "b", count: 64)))
        let googleKey = "google/" + google.accountHash
        let oneDriveKey = "oneDrive/" + oneDrive.accountHash
        defer { tracker.prepareDestinations([:]); tracker.discard(id) }
        tracker.prepareDestinations([id: [.init(destination: google), .init(destination: oneDrive)]])
        tracker.startDestination(id, destination: google)
        tracker.setDestination(id, destination: google, fraction: 1)
        XCTAssertEqual(tracker.destinations[id]?[googleKey]?.fraction, 0.99)
        XCTAssertEqual(tracker.destinations[id]?[oneDriveKey]?.fraction, 0)
        tracker.finishDestination(id, destination: google)
        tracker.setDestination(id, destination: google, fraction: 0.3)
        XCTAssertEqual(tracker.destinations[id]?[googleKey]?.fraction, 1)
        tracker.startDestination(id, destination: oneDrive)
        tracker.stopDestination(id, destination: oneDrive)
        tracker.setDestination(id, destination: oneDrive, fraction: 0.7)
        XCTAssertEqual(tracker.destinations[id]?[oneDriveKey]?.fraction, 0)
    }
    func testPersonalAndOrganizationPendingQueuesDoNotEraseEachOther() {
        let tracker = CloudUploadProgress.shared
        let personal = UUID(), business = UUID()
        defer { tracker.preparePending([]); tracker.prepareBusinessPending([]); tracker.discard(personal); tracker.discard(business) }
        tracker.prepareBusinessPending([business])
        tracker.preparePending([personal])
        XCTAssertEqual(tracker.values[business], 0)
        XCTAssertEqual(tracker.values[personal], 0)
        tracker.preparePending([])
        XCTAssertEqual(tracker.values[business], 0)
        XCTAssertNil(tracker.values[personal])
    }
    func testTransferDoesNotClaimCompletionBeforeVerification() {
        let tracker = CloudUploadProgress.shared
        let id = UUID()
        defer { tracker.discard(id) }
        tracker.start(id)
        tracker.set(id, fraction: 1)
        XCTAssertEqual(tracker.values[id], 0.99)
        tracker.finish(id)
        XCTAssertEqual(tracker.values[id], 1)
        tracker.set(id, fraction: 0.5)
        XCTAssertEqual(tracker.values[id], 1)
    }

    func testFailedTransferCannotBeRevivedByLateCallbacks() {
        let tracker = CloudUploadProgress.shared
        let id = UUID()
        tracker.start(id)
        defer { tracker.discard(id) }
        tracker.stop(id)
        tracker.set(id, fraction: 0.8)
        XCTAssertEqual(tracker.values[id], 0)
    }

    func testNonFiniteInputIsIgnoredAndProgressUsesWholePercentages() {
        let tracker = CloudUploadProgress.shared
        let id = UUID()
        defer { tracker.discard(id) }
        tracker.start(id)
        tracker.set(id, fraction: .nan)
        XCTAssertEqual(tracker.values[id], 0)
        tracker.set(id, fraction: 0.426)
        XCTAssertEqual(tracker.values[id], 0.42)
    }

    func testWaitingItemsAreMarkedBeforeTheirTurn() {
        let tracker = CloudUploadProgress.shared
        let first = UUID(), second = UUID()
        defer { tracker.discard(first); tracker.discard(second) }
        tracker.preparePending([first, second])
        XCTAssertEqual(tracker.values[first], 0)
        XCTAssertEqual(tracker.values[second], 0)
        tracker.preparePending([second])
        XCTAssertNil(tracker.values[first])
        XCTAssertEqual(tracker.values[second], 0)
    }

    func testRemainingMaskClearsClockwiseFromTheTop() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let corners = [CGPoint(x: 75, y: 25), CGPoint(x: 75, y: 75),
                       CGPoint(x: 25, y: 75), CGPoint(x: 25, y: 25)]
        for step in 0...4 {
            let path = CloudUploadRemainingMask(progress: Double(step) / 4).path(in: rect).cgPath
            for (index, point) in corners.enumerated() {
                XCTAssertEqual(path.contains(point), index >= step,
                               "Quadrante \(index) em \(step * 25)%")
            }
        }
    }
}
