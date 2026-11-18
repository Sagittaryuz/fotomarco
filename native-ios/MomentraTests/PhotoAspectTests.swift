import XCTest
import UIKit
@testable import Momentra

final class PhotoAspectTests: XCTestCase {
    func testCenteredCropKeepsTargetAspectInBothOrientations() throws {
        for source in [CGSize(width: 4032, height: 3024), CGSize(width: 3024, height: 4032)] {
            for aspect in PhotoAspect.allCases {
                let crop = try XCTUnwrap(aspect.crop(in: source))
                let expected: CGFloat = aspect == .standard ? 4.0 / 3.0 : aspect == .wide ? 16.0 / 9.0 : 1
                let actual = source.width >= source.height ? crop.width / crop.height : crop.height / crop.width
                XCTAssertEqual(actual, expected, accuracy: 0.002)
                XCTAssertLessThanOrEqual(crop.maxX, source.width)
                XCTAssertLessThanOrEqual(crop.maxY, source.height)
                XCTAssertEqual(crop.midX, source.width / 2, accuracy: 0.001)
                XCTAssertEqual(crop.midY, source.height / 2, accuracy: 0.001)
            }
        }
    }

    func testRejectsInvalidDimensions() {
        XCTAssertNil(PhotoAspect.standard.crop(in: .zero))
        XCTAssertNil(PhotoAspect.wide.crop(in: CGSize(width: CGFloat.infinity, height: 100)))
    }

    func testPreviewFitsAvailableBoundsWithoutChangingAspect() throws {
        for bounds in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            for aspect in PhotoAspect.allCases {
                let size = try XCTUnwrap(aspect.fittedSize(in: bounds))
                let ratio: CGFloat = aspect == .standard ? 4.0 / 3.0 : aspect == .wide ? 16.0 / 9.0 : 1
                let actual = bounds.width >= bounds.height ? size.width / size.height : size.height / size.width
                XCTAssertEqual(actual, ratio, accuracy: 0.0001)
                XCTAssertLessThanOrEqual(size.width, bounds.width)
                XCTAssertLessThanOrEqual(size.height, bounds.height)
            }
        }
    }

    func testRenderedPhotoUsesRequestedDimensions() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let input = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        let output = try XCTUnwrap(StampRenderer.render(input, aspect: .wide, snapshot: nil))
        let result = try XCTUnwrap(UIImage(data: output))
        XCTAssertEqual(result.size.width, 400, accuracy: 1)
        XCTAssertEqual(result.size.height, 225, accuracy: 1)
        let squareOutput = try XCTUnwrap(StampRenderer.render(input, aspect: .square, snapshot: nil))
        let square = try XCTUnwrap(UIImage(data: squareOutput))
        XCTAssertEqual(square.size.width, 300, accuracy: 1)
        XCTAssertEqual(square.size.height, 300, accuracy: 1)
    }
}
