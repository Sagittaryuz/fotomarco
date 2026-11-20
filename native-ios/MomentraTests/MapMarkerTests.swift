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
        var yellow = 0
        var dark = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            let alpha = pixels[offset + 3]
            guard alpha > 200 else { continue }
            if red > 180 && green > 140 && blue < 120 { yellow += 1 }
            if red < 60 && green < 60 && blue < 60 { dark += 1 }
        }
        XCTAssertGreaterThan(yellow, 500)
        XCTAssertGreaterThan(dark, 20)
    }
}
