import XCTest
@testable import Momentra

final class PhotoProfileIndexTests: XCTestCase {
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

    func testPinchChangesColumnCountWithinBounds() {
        XCTAssertEqual(GalleryZoom.next(columns: 3, magnification: 1.5), 2)
        XCTAssertEqual(GalleryZoom.next(columns: 3, magnification: 0.7), 5)
        XCTAssertEqual(GalleryZoom.next(columns: 8, magnification: 0.7), 8)
        XCTAssertEqual(GalleryZoom.next(columns: 2, magnification: 1.5), 2)
    }
}
