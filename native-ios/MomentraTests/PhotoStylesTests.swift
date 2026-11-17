import XCTest
import UIKit
@testable import Momentra

final class PhotoStylesTests: XCTestCase {
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
}
