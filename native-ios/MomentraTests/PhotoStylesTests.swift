import XCTest
import UIKit
import CoreImage
@testable import Momentra

final class PhotoStylesTests: XCTestCase {
    func testLiveRecipeMatchesCapturedStyle() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 10))
        let source = renderer.image { context in
            UIColor(red: 0.7, green: 0.3, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 10))
        }
        let input = try XCTUnwrap(CIImage(image: source))
        let context = CIContext(options: [.cacheIntermediates: false])
        let adjustments = PhotoStyleAdjustments(tone: -25, color: 20, palette: 85)
        for style in MomentraPhotoStyle.allCases {
            let live = style.apply(to: input, adjustments: adjustments)
            let captured = style.apply(to: source, adjustments: adjustments)
            let liveImage = try XCTUnwrap(context.createCGImage(live, from: input.extent))
            let liveData = try XCTUnwrap(UIImage(cgImage: liveImage, scale: source.scale, orientation: source.imageOrientation).pngData())
            XCTAssertEqual(liveData, captured.pngData(), "Style \(style.rawValue)")
        }
    }

    func testPreviewFitMirrorsAndFillsTheRequestedBounds() {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 1, y: 0, width: 1, height: 1))
        let image = blue.composited(over: red)
        let mirrored = CameraStylePreviewRenderer.fit(image, to: CGSize(width: 2, height: 1), rotation: 0, mirror: true)
        XCTAssertEqual(mirrored.extent, CGRect(x: 0, y: 0, width: 2, height: 1))
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            CIContext().render(mirrored, toBitmap: address, rowBytes: 8, bounds: mirrored.extent,
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        XCTAssertGreaterThan(bytes[2], 240)
        XCTAssertGreaterThan(bytes[4], 240)
        let rotated = CameraStylePreviewRenderer.fit(image, to: CGSize(width: 1, height: 2), rotation: 90, mirror: false)
        XCTAssertEqual(rotated.extent, CGRect(x: 0, y: 0, width: 1, height: 2))
    }

    func testNaturalPreservesTheSourceImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let source = renderer.image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        XCTAssertTrue(MomentraPhotoStyle.natural.apply(to: source) === source)
    }

    func testStylesProduceImagesAtOriginalDimensions() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 10))
        let source = renderer.image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 12, height: 10)) }
        for style in MomentraPhotoStyle.allCases {
            let output = style.apply(to: source)
            XCTAssertEqual(output.size, source.size, "Style \(style.rawValue)")
            XCTAssertNotNil(output.cgImage)
        }
    }

    func testCustomToneAndPaletteAreAppliedToNaturalStyle() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let source = renderer.image { context in
            UIColor(red: 0.7, green: 0.3, blue: 0.1, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let edited = MomentraPhotoStyle.natural.apply(to: source, adjustments: .init(tone: -60, color: 0, palette: 50))
        XCTAssertEqual(edited.size, source.size)
        XCTAssertNotEqual(try XCTUnwrap(edited.pngData()), try XCTUnwrap(source.pngData()))
    }
}
