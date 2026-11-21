import XCTest
@testable import Momentra

@MainActor
final class CloudUploadProgressTests: XCTestCase {
    func testTransferDoesNotClaimCompletionBeforeVerification() {
        let tracker = CloudUploadProgress.shared
        let id = UUID()
        defer { tracker.stop(id) }
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
        tracker.stop(id)
        tracker.set(id, fraction: 0.8)
        XCTAssertNil(tracker.values[id])
    }

    func testNonFiniteInputIsIgnoredAndProgressUsesWholePercentages() {
        let tracker = CloudUploadProgress.shared
        let id = UUID()
        defer { tracker.stop(id) }
        tracker.start(id)
        tracker.set(id, fraction: .nan)
        XCTAssertEqual(tracker.values[id], 0)
        tracker.set(id, fraction: 0.426)
        XCTAssertEqual(tracker.values[id], 0.42)
    }
}
