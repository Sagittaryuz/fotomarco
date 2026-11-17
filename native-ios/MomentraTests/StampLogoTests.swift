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
}
