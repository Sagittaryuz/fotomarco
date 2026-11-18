import XCTest
import AVFoundation
@testable import Momentra

final class FlashCycleTests: XCTestCase {
    func testCycleUsesAllSupportedModes() {
        let modes: [AVCaptureDevice.FlashMode] = [.off, .on, .auto]
        XCTAssertEqual(FlashCycle.next(current: .off, supported: modes), .on)
        XCTAssertEqual(FlashCycle.next(current: .on, supported: modes), .auto)
        XCTAssertEqual(FlashCycle.next(current: .auto, supported: modes), .off)
    }

    func testCycleSkipsUnsupportedModes() {
        XCTAssertEqual(FlashCycle.next(current: .on, supported: [.off, .on]), .off)
        XCTAssertEqual(FlashCycle.next(current: .off, supported: [.off]), .off)
        XCTAssertEqual(FlashCycle.next(current: .auto, supported: []), .off)
    }
}
