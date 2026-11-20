import XCTest
@testable import Momentra

final class CameraPreviewFrameTests: XCTestCase {
    func testTallAspectNarrowerThanTheScreenWhenHeightIsLimited() {
        let frame = PhotoAspect.wide.previewFrame(in: CGSize(width: 390, height: 780), top: 35, bottom: 535)
        XCTAssertEqual(frame.minY, 35, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 535, accuracy: 0.001)
        XCTAssertEqual(frame.width / frame.height, 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 195, accuracy: 0.001)
    }

    func testEveryAspectStaysInsideTheControlsOnCompactAndWideScreens() {
        for screen in [CGSize(width: 390, height: 480), CGSize(width: 820, height: 365)] {
            for aspect in PhotoAspect.allCases {
                let frame = aspect.previewFrame(in: screen, top: 35, bottom: 260)
                XCTAssertGreaterThanOrEqual(frame.minY, 35)
                XCTAssertLessThanOrEqual(frame.maxY, 260.001)
                XCTAssertLessThanOrEqual(frame.width, screen.width)
                XCTAssertEqual(frame.width / frame.height,
                               screen.width >= screen.height ? aspect.landscapeRatio : 1 / aspect.landscapeRatio,
                               accuracy: 0.001)
            }
        }
    }

    func testUnmeasuredControlsDoNotShowAnUnboundedPreview() {
        XCTAssertEqual(PhotoAspect.standard.previewFrame(in: CGSize(width: 390, height: 780), top: 35, bottom: 0), .zero)
    }

    func testAllAspectsKeepTheStandardFrameTop() {
        for screen in [CGSize(width: 390, height: 844), CGSize(width: 320, height: 568),
                       CGSize(width: 844, height: 390)] {
            let top: CGFloat = 60
            let bottom = screen.height - 130
            let reference = PhotoAspect.standard.previewFrame(in: screen, top: top, bottom: bottom)
            for aspect in PhotoAspect.allCases {
                let frame = aspect.previewFrame(in: screen, top: top, bottom: bottom)
                XCTAssertEqual(frame.minY, reference.minY, accuracy: 0.001)
                XCTAssertLessThanOrEqual(frame.maxY, bottom + 0.001)
            }
        }
    }
}
