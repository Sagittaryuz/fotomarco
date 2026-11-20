import XCTest
import UIKit
@testable import Momentra

final class MapMarkerTests: XCTestCase {
    func testRenderedMarkerContainsYellowCircleAndDarkArrow() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80), format: format).image { output in
            StampRenderer.drawLocationMarker(center: CGPoint(x: 40, y: 40), diameter: 60, context: output.cgContext)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 80 * 80 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 80, height: 80, bitsPerComponent: 8,
                                               bytesPerRow: 80 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 80, height: 80))
        let yellow = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 180 && pixels[$0 + 1] > 140 && pixels[$0 + 2] < 120 && pixels[$0 + 3] > 200
        }.count
        let dark = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 60 && pixels[$0 + 1] < 60 && pixels[$0 + 2] < 60 && pixels[$0 + 3] > 200
        }.count
        XCTAssertGreaterThan(yellow, 500)
        XCTAssertGreaterThan(dark, 20)
    }
}
