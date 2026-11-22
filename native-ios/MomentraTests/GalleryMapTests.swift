import XCTest
@testable import Momentra

final class GalleryMapTests: XCTestCase {
    func testIndexPrecomputesZoomLevelsAndKeepsEveryPhoto() throws {
        let records = [GalleryMapRecord(id: "a", latitude: -17.88, longitude: -51.71),
                       GalleryMapRecord(id: "b", latitude: -17.879, longitude: -51.709)]
        let index = GalleryMapIndex.build(records)
        XCTAssertEqual(index.levels.count, 21)
        XCTAssertEqual(index.levels[0].first?.itemIDs.count, 2)
        XCTAssertEqual(index.levels[20].count, 2)
        XCTAssertEqual(GalleryMapIndex.zoom(for: 360), 0)
        let restored = try JSONDecoder().decode(GalleryMapIndex.self, from: JSONEncoder().encode(index))
        XCTAssertEqual(restored.records, index.records)
        XCTAssertEqual(restored.levels[0].first?.itemIDs.count, 2)
    }
    func testNearbyPhotosSeparateWhenZoomingIn() {
        let farA = GalleryMapBinning.key(latitude: -17.88, longitude: -51.71, span: 40)
        let farB = GalleryMapBinning.key(latitude: -17.87, longitude: -51.70, span: 40)
        let nearA = GalleryMapBinning.key(latitude: -17.88, longitude: -51.71, span: 0.01)
        let nearB = GalleryMapBinning.key(latitude: -17.87, longitude: -51.70, span: 0.01)
        XCTAssertEqual(farA, farB)
        XCTAssertNotEqual(nearA, nearB)
    }
}
