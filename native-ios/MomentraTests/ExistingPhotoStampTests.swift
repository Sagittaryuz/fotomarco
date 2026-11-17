import XCTest
import UIKit
import CoreLocation
@testable import Momentra

final class ExistingPhotoStampTests: XCTestCase {
    func testUsesOnlyAvailableMetadata() {
        let zone = TimeZone(secondsFromGMT: 0)!
        XCTAssertTrue(ExistingPhotoStamp.lines(date: nil, location: nil, timeZone: zone).isEmpty)
        let date = Date(timeIntervalSince1970: 0)
        let lines = ExistingPhotoStamp.lines(date: date, location: nil, timeZone: zone)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("01/01/1970"))
        XCTAssertFalse(lines[0].contains("Lat"))
        let coordinate = CLLocation(latitude: -17.9, longitude: -51.7)
        let located = ExistingPhotoStamp.lines(date: nil, location: coordinate, timeZone: zone)
        XCTAssertEqual(located.count, 1)
        XCTAssertTrue(located[0].contains("-17.900000"))
    }

    func testProducesCopyWithoutCroppingAndDoesNotStampWhenNoData() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let original = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        XCTAssertNil(ExistingPhotoStamp.render(original, lines: []))
        let copy = try XCTUnwrap(ExistingPhotoStamp.render(original, lines: ["01/01/1970 00:00:00 GMT+00:00"]))
        let rendered = try XCTUnwrap(UIImage(data: copy))
        XCTAssertEqual(rendered.size.width, 400)
        XCTAssertEqual(rendered.size.height, 200)
        XCTAssertNotEqual(copy, original)
    }
}
