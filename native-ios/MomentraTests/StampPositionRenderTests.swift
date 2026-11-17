import XCTest
import UIKit
@testable import Momentra

final class StampPositionRenderTests: XCTestCase {
    func testLongStampShrinksInsteadOfBeingClipped() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let text = String(repeating: "Endereço com informações completas de localização e data. ", count: 8) as NSString
        let layout = try XCTUnwrap(StampRenderer.fitText(text, width: 150, maxHeight: 200, initialSize: 24, style: "system", paragraph: paragraph))
        XCTAssertLessThan(layout.font.pointSize, 24)
        XCTAssertLessThanOrEqual(layout.height, 200)
        XCTAssertNil(StampRenderer.fitText(String(repeating: "dados ", count: 10_000) as NSString,
            width: 20, maxHeight: 10, initialSize: 12, style: "system", paragraph: paragraph))
    }

    func testRenderedStampMovesBetweenTopAndBottom() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 400, height: 600)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 40, width: 400, height: 8))
        }
        let input = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        func counts(_ position: String) throws -> (red: [Int], dark: [Int]) {
            let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, position: position, location: nil, heading: nil)
            let data = try XCTUnwrap(StampRenderer.render(input, aspect: .standard, snapshot: snapshot))
            let cg = try XCTUnwrap(UIImage(data: data)?.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            var red = [0, 0], dark = [0, 0]
            for y in 0..<cg.height {
                let half = y < cg.height / 2 ? 0 : 1
                for x in 0..<cg.width {
                    let p = (y * cg.width + x) * 4
                    if pixels[p] > 180 && pixels[p+1] < 80 && pixels[p+2] < 80 { red[half] += 1 }
                    if pixels[p] < 150 && pixels[p+1] < 150 && pixels[p+2] < 150 { dark[half] += 1 }
                }
            }
            return (red, dark)
        }
        let top = try counts("top")
        let bottom = try counts("bottom")
        let topHalf = top.red[0] > top.red[1] ? 0 : 1
        let bottomHalf = 1 - topHalf
        XCTAssertGreaterThan(top.red[topHalf], 100)
        XCTAssertGreaterThan(top.dark[topHalf], top.dark[bottomHalf] + 500)
        XCTAssertGreaterThan(bottom.dark[bottomHalf], bottom.dark[topHalf] + 500)
    }
}
