import XCTest
import SwiftUI
@testable import Momentra

@MainActor
final class CloudUploadProgressTests: XCTestCase {
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
