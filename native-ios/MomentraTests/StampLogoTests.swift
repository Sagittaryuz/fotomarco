import XCTest
import UIKit
@testable import Momentra

final class StampLogoTests: XCTestCase {
    func testLogoIsRenderedIntoProcessedPhoto() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let base = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let logo = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, logo: logo, location: nil, heading: nil)
        let input = try XCTUnwrap(base.jpegData(compressionQuality: 1))
        let data = try XCTUnwrap(StampRenderer.render(input, aspect: .standard, snapshot: snapshot))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let color = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: color, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let redPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 160 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80 }.count
        XCTAssertGreaterThan(redPixels, 50)
    }

    func testLogoPathRejectsDirectories() {
        XCTAssertNil(ProfileLogoStore.load("../outside.png"))
    }

    func testLogoCornersAvoidStampAndRemainInsideImage() throws {
        let image = CGSize(width: 400, height: 600)
        let stamp = CGRect(x: 14, y: 450, width: 372, height: 136)
        let logo = CGSize(width: 50, height: 30)
        let safe = CGRect(x: 14, y: 14, width: 372, height: 572)
        for corner in ["top-left", "top-right", "bottom-left", "bottom-right", "auto"] {
            let rect = try XCTUnwrap(StampRenderer.logoRect(imageSize: image, logoSize: logo, stamp: stamp,
                margin: 14, corner: corner, stampPosition: "bottom"))
            XCTAssertTrue(safe.contains(rect))
            XCTAssertFalse(rect.intersects(stamp))
            if corner.hasSuffix("-left") { XCTAssertEqual(rect.minX, 14) }
            if corner.hasSuffix("-right") { XCTAssertEqual(rect.maxX, 386) }
        }
        XCTAssertNil(StampRenderer.logoRect(imageSize: CGSize(width: 50, height: 50), logoSize: CGSize(width: 40, height: 40),
            stamp: CGRect(x: 5, y: 5, width: 40, height: 40), margin: 5, corner: "top-left", stampPosition: "top"))
    }

    func testLongAddressStillLeavesSpaceForLogo() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let base = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let logo = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, title: String(repeating: "A", count: 40),
            note: String(repeating: "B", count: 96), logo: logo, logoCorner: "bottom-right", location: nil, heading: nil)
        let result = StampRenderer.render(try XCTUnwrap(base.jpegData(compressionQuality: 1)), aspect: .standard,
            snapshot: snapshot, address: String(repeating: "Rua Exemplo ", count: 20))
        XCTAssertNotNil(result)
    }
}
