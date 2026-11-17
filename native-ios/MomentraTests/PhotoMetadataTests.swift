import XCTest
import CoreLocation
import ImageIO
@testable import Momentra

final class PhotoMetadataTests: XCTestCase {
    func testOldLocationIsRemovedAndCameraFieldsAreRetained() {
        let original: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [kCGImagePropertyGPSLatitude as String: 42],
            kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFModel as String: "Camera"],
            kCGImagePropertyOrientation as String: 6
        ]
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, location: nil, heading: nil)
        let result = PhotoMetadata.properties(original: original, snapshot: snapshot, size: CGSize(width: 400, height: 300))
        XCTAssertNil(result[kCGImagePropertyGPSDictionary as String])
        XCTAssertEqual(result[kCGImagePropertyOrientation as String] as? Int, 1)
        XCTAssertEqual((result[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFModel as String] as? String, "Camera")
    }

    func testOnlyCurrentEnabledLocationIsEncoded() throws {
        let now = Date()
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.9, longitude: -51.7), altitude: 700, horizontalAccuracy: 8, verticalAccuracy: -1, timestamp: now)
        let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: true, location: location, heading: nil)
        let result = PhotoMetadata.properties(original: [:], snapshot: snapshot, size: CGSize(width: 400, height: 300))
        let gps = try XCTUnwrap(result[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitudeRef as String] as? String, "S")
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitudeRef as String] as? String, "W")
        XCTAssertNil(gps[kCGImagePropertyGPSAltitude as String])
    }
}
