import XCTest
import CoreLocation
@testable import Momentra

final class PhotoProfileIndexTests: XCTestCase {
    func testCloudDiscoveredLegacyAssociationRetainsExistingProfile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), org = UUID(), old = CaptureProfileTag(id: UUID(), name: "Anterior")
        try PhotoProfileIndex.register(captureID: id, profile: old, root: root)
        try PhotoProfileIndex.associateLegacyCapture(id, captureDate: Date(timeIntervalSince1970: 100), organizationID: org,
            name: "JMD Hamoa", before: Date(timeIntervalSince1970: 200), root: root)
        XCTAssertEqual(PhotoProfileIndex.load(root: root).captures[id]?.id, org)
        let data = try Data(contentsOf: root.appendingPathComponent("CaptureProfiles/\(id.uuidString).json"))
        XCTAssertEqual(try JSONDecoder().decode(CaptureProfileRecord.self, from: data).profile, old)
        XCTAssertThrowsError(try PhotoProfileIndex.associateLegacyCapture(id, captureDate: Date(timeIntervalSince1970: 100),
            organizationID: UUID(), name: "Outro", before: Date(timeIntervalSince1970: 200), root: root))
    }
    func testLegacyAssociationPreservesOriginalProfileAndSkipsNewCaptures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = UUID(), newer = UUID(), original = CaptureProfileTag(id: UUID(), name: "Anterior"), org = UUID()
        try PhotoProfileIndex.register(captureID: old, profile: original, captureDate: Date(timeIntervalSince1970: 100), root: root)
        try PhotoProfileIndex.register(captureID: newer, profile: original, captureDate: Date(timeIntervalSince1970: 300), root: root)
        try PhotoProfileIndex.bindLocal(captureID: old, assetID: "asset", root: root)
        XCTAssertEqual(try PhotoProfileIndex.associateLegacyCaptures(organizationID: org, name: "JMD Hamoa", before: Date(timeIntervalSince1970: 200), root: root), 1)
        let index = PhotoProfileIndex.load(root: root)
        XCTAssertEqual(index.captures[old], CaptureProfileTag(id: org, name: "JMD Hamoa"))
        XCTAssertEqual(index.assets["asset"]?.id, org)
        XCTAssertEqual(index.captures[newer], original)
        XCTAssertEqual(try PhotoProfileIndex.associateLegacyCaptures(organizationID: org, name: "JMD Hamoa", before: Date(timeIntervalSince1970: 200), root: root), 0)
        let stored = try Data(contentsOf: root.appendingPathComponent("CaptureProfiles/\(old.uuidString).json"))
        XCTAssertEqual(try JSONDecoder().decode(CaptureProfileRecord.self, from: stored).profile, original)
    }
    func testCaptureCoordinatesPersistForMapWithoutChangingPhoto() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try PhotoProfileIndex.register(captureID: id, profile: .init(id: UUID(), name: "Obra"),
                                       root: root, location: CLLocation(latitude: -17.88, longitude: -51.71))
        let location = try XCTUnwrap(PhotoProfileIndex.load(root: root).locations[id])
        XCTAssertEqual(location.latitude, -17.88, accuracy: 0.00001)
        XCTAssertEqual(location.longitude, -51.71, accuracy: 0.00001)
    }
    func testAssociationsPersistWithoutChangingTheImage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let profile = CaptureProfileTag(id: UUID(), name: "Obra")
        try PhotoProfileIndex.register(captureID: id, profile: profile, root: root)
        try PhotoProfileIndex.bindLocal(captureID: id, assetID: "asset-1", root: root)
        try PhotoProfileIndex.bindCloud(captureID: id, owner: "account-a", mediaID: "media-1", root: root)
        let index = PhotoProfileIndex.load(root: root)
        XCTAssertEqual(index.captures[id], profile)
        XCTAssertEqual(index.assets["asset-1"], profile)
        XCTAssertEqual(index.assetCaptures["asset-1"], id)
        XCTAssertEqual(index.cloud[PhotoProfileIndex.cloudKey(owner: "account-a", mediaID: "media-1")], profile)
        XCTAssertNil(index.cloud[PhotoProfileIndex.cloudKey(owner: "account-b", mediaID: "media-1")])
    }

    func testGroupingUsesDateAndProfileWithoutGuessingMissingData() {
        struct Photo { let date: Date?; let profile: CaptureProfileTag? }
        let profile = CaptureProfileTag(id: UUID(), name: "Padrão")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let photos = [Photo(date: date, profile: profile), Photo(date: date, profile: nil),
                      Photo(date: nil, profile: nil)]
        let groups = GalleryGrouping.groups(photos, date: { $0.date }, profile: { $0.profile })
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.last?.title, "Sem data · Sem perfil")
        XCTAssertEqual(groups.filter { $0.profile?.id == profile.id }.count, 1)
    }

    func testCloudFilenameCarriesProfileWithoutPuttingNameOnPhoto() {
        let profile = CaptureProfileTag(id: UUID(), name: "Padrão")
        let filename = CloudProfileFilename.encode(captureID: UUID(), profile: profile)
        XCTAssertEqual(CloudProfileFilename.decode(filename), profile)
        let original = CloudProfileFilename.encode(captureID: UUID(), profile: profile, originalExtension: "heic")
        XCTAssertEqual(CloudProfileFilename.decode(original), profile)
        XCTAssertNil(CloudProfileFilename.decode("unrelated.jpg"))
    }

    func testGalleryDateHeadersPutTheWeekdayAfterTheLongDate() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2020, month: 11, day: 18, hour: 12)))
        let past = GalleryGroup<Int>(date: date, profile: nil, items: [], showsProfile: false)
        XCTAssertEqual(past.title, "18 de novembro de 2020 · quarta-feira")
        let today = GalleryGroup<Int>(date: Calendar.current.startOfDay(for: .now), profile: nil, items: [], showsProfile: false)
        XCTAssertEqual(today.title.components(separatedBy: " · ").count, 3)
        XCTAssertTrue(today.title.hasPrefix("Hoje · "))
        let undated = GalleryGroup<Int>(date: nil, profile: nil, items: [], showsProfile: false)
        XCTAssertEqual(undated.title, "Sem data")
    }

    func testPinchChangesColumnCountWithinBounds() {
        XCTAssertEqual(GalleryZoom.next(columns: 3, magnification: 1.5), 2)
        XCTAssertEqual(GalleryZoom.next(columns: 3, magnification: 0.7), 5)
        XCTAssertEqual(GalleryZoom.next(columns: 8, magnification: 0.7), 8)
        XCTAssertEqual(GalleryZoom.next(columns: 2, magnification: 1.5), 2)
    }
}

