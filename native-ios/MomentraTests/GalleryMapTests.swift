import XCTest
import MapKit
@testable import Momentra

final class GalleryMapTests: XCTestCase {
    func testFramingCoversPhotosAndUsesAUsefulZoomForOneLocation() throws {
        let points = [CLLocationCoordinate2D(latitude: -17.9, longitude: -51.8),
                      CLLocationCoordinate2D(latitude: -17.7, longitude: -51.4)]
        let region = try XCTUnwrap(GalleryMapFraming.region(for: points))
        XCTAssertEqual(region.center.latitude, -17.8, accuracy: 0.00001)
        XCTAssertEqual(region.center.longitude, -51.6, accuracy: 0.00001)
        XCTAssertGreaterThan(region.span.latitudeDelta, 0.2)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0.4)
        let single = try XCTUnwrap(GalleryMapFraming.region(for: [points[0]]))
        XCTAssertGreaterThan(single.span.latitudeDelta, 0)
        XCTAssertLessThan(single.span.latitudeDelta, 0.02)
        XCTAssertNil(GalleryMapFraming.region(for: []))
    }

    func testFramingUsesShortRouteAcrossDateLineAndRejectsInvalidCoordinates() throws {
        let region = try XCTUnwrap(GalleryMapFraming.region(for: [
            .init(latitude: 0, longitude: 179), .init(latitude: 0, longitude: -179),
            .init(latitude: .nan, longitude: 0)]))
        XCTAssertEqual(abs(region.center.longitude), 180, accuracy: 0.00001)
        XCTAssertLessThan(region.span.longitudeDelta, 5)
    }
    func testPhotosAtIdenticalCoordinatesRemainDistinctAndInOrder() {
        let first = UUID(), second = UUID(), missing = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func photo(_ id: UUID) -> GalleryItem {
            let file = OriginalFile(url: URL(fileURLWithPath: "/Processed/\(id.uuidString).jpg"),
                                    isVideo: false, isProcessed: true, date: date)
            return GalleryItem(source: .capture(file), date: date, profile: nil)
        }
        let photos = [photo(first), photo(second), photo(missing)]
        let records = [GalleryMapRecord(id: first.uuidString, latitude: -17.88, longitude: -51.71),
                       GalleryMapRecord(id: second.uuidString, latitude: -17.88, longitude: -51.71)]
        let markers = GalleryMapMarker.project(photos, records: records)
        XCTAssertEqual(markers.map(\.id), [first.uuidString, second.uuidString])
        XCTAssertEqual(markers.map(\.item.id), [photos[0].id, photos[1].id])
        XCTAssertEqual(markers[0].coordinate.latitude, markers[1].coordinate.latitude)
        XCTAssertEqual(markers[0].coordinate.longitude, markers[1].coordinate.longitude)
    }

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
