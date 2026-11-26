import XCTest
import CoreImage
import CoreLocation
@testable import Momentra

final class StampLocationQRTests: XCTestCase {
    func testQRDecodesToCapturedCoordinates() throws {
        let coordinate = CLLocationCoordinate2D(latitude: -17.897183, longitude: -51.726411)
        let image = try XCTUnwrap(StampLocationQR.image(for: coordinate))
        let cgImage = try XCTUnwrap(image.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let feature = try XCTUnwrap(detector.features(in: CIImage(cgImage: cgImage)).first as? CIQRCodeFeature)
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(feature.messageString)))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "query" })?.value, "-17.897183,-51.726411")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "api" })?.value, "1")
    }

    func testExistingLayoutDefaultsToNoQR() throws {
        let layout = try JSONDecoder().decode(StampLayout.self, from: Data("{}".utf8))
        XCTAssertFalse(layout.showsLocationQR)
        XCTAssertNil(StampLocationQR.url(for: CLLocationCoordinate2D(latitude: 91, longitude: 0)))
    }

    func testCornerMatchesRelativePositionNotOnlyExactCoordinates() {
        let upperLeft = StampPoint(x: 0, y: 0)
        XCTAssertTrue(StampPoint(x: 0.15, y: 0.13).sharesCorner(with: upperLeft))
        XCTAssertFalse(StampPoint(x: 0.85, y: 0.13).sharesCorner(with: upperLeft))
        XCTAssertFalse(StampPoint(x: 0.15, y: 0.90).sharesCorner(with: upperLeft))
    }

    func testQRIsPresentOnSavedOverlayOnlyWithValidLocation() throws {
        var layout = StampLayout()
        layout.mode = .separate
        layout.showsMap = false; layout.showsInformation = false; layout.showsLogo = false
        layout.showsLocationQR = true
        let now = Date()
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.897183, longitude: -51.726411),
                                  altitude: 0, horizontalAccuracy: 8, verticalAccuracy: 8, timestamp: now)
        let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: true, location: location, heading: nil, layout: layout)
        let overlay = try XCTUnwrap(StampRenderer.overlay(size: CGSize(width: 1600, height: 2000), snapshot: snapshot, map: nil, address: nil))
        let cgImage = try XCTUnwrap(overlay.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let codes = detector.features(in: CIImage(cgImage: cgImage)).compactMap { $0 as? CIQRCodeFeature }
        XCTAssertEqual(codes.count, 1)
        XCTAssertTrue(codes.first?.messageString?.contains("-17.897183") == true)

        let withoutLocation = StampSnapshot(capturedAt: now, gpsEnabled: false, location: location, heading: nil, layout: layout)
        let empty = try XCTUnwrap(StampRenderer.overlay(size: CGSize(width: 1600, height: 2000), snapshot: withoutLocation, map: nil, address: nil))
        XCTAssertTrue(detector.features(in: CIImage(cgImage: try XCTUnwrap(empty.cgImage))).isEmpty)
    }
}
