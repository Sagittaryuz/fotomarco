import XCTest
@testable import Momentra

@MainActor
final class GalleryDuplicateTests: XCTestCase {
    func testCombinesStorageDestinationsWithoutCombiningOriginalAndProcessed() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = CaptureProfileTag(id: UUID(), name: "Obra")
        let processedURL = URL(fileURLWithPath: "/Processed/" + id.uuidString + ".jpg")
        let originalURL = URL(fileURLWithPath: "/Originals/" + id.uuidString + ".heic")
        let processed = GalleryItem(source: .capture(.init(url: processedURL, isVideo: false, isProcessed: true, date: date)),
                                    date: date, profile: profile)
        let original = GalleryItem(source: .capture(.init(url: originalURL, isVideo: false, isProcessed: false, date: date)),
                                   date: date, profile: profile)
        let drives = try [
            cloud(.googleDrive, account: "a", id: id, date: date),
            cloud(.googleDrive, account: "b", id: id, date: date),
            cloud(.oneDrive, account: "c", id: id, date: date)
        ]
        let sources = [processed, original] + drives + [drives[0]]
        let groups = GalleryItem.grouped(sources, origin: nil, profile: nil)
        XCTAssertEqual(groups.count, 2)
        let combined = try XCTUnwrap(groups.first { $0.id == processed.id })
        XCTAssertEqual(combined.storageID, processed.storageID)
        XCTAssertEqual(combined.storageBadges.map(\.origin), [.local, .google, .google, .oneDrive])
        let filtered = GalleryItem.grouped(sources, origin: .oneDrive, profile: profile.id)
        XCTAssertEqual(filtered.map(\.id), [processed.id])
        XCTAssertEqual(filtered.first?.storageID, drives[2].storageID)
        XCTAssertEqual(filtered.first?.storageBadges.count, 4)
        XCTAssertFalse(filtered.first?.storageBadges.contains(where: { $0.label.contains("missing") }) ?? true)
    }

    func testRecognizesLegacyCloudFavoriteAndRespectsGroupedChoice() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let file = OriginalFile(url: URL(fileURLWithPath: "/Processed/" + id.uuidString + ".jpg"),
                                isVideo: false, isProcessed: true, date: date)
        let local = GalleryItem(source: .capture(file), date: date, profile: nil)
        let remote = try cloud(.oneDrive, account: "c", id: id, date: date)
        guard case .cloud(let item) = remote.source else { return XCTFail("Missing cloud fixture") }
        let grouped = try XCTUnwrap(GalleryItem.grouped([local, remote], origin: nil, profile: nil).first)
        XCTAssertTrue(grouped.isFavorite(in: [], cloud: [item.favoriteKey], device: [:]))
        XCTAssertFalse(grouped.isFavorite(in: ["unfavorite/" + grouped.id], cloud: [item.favoriteKey], device: [:]))
        XCTAssertTrue(grouped.isFavorite(in: [grouped.id], cloud: [], device: [:]))
    }

    func testCloudSnapshotSkipsOnlyEquivalentListings() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let old = try cloud(.googleDrive, account: "a", id: id, date: date, revision: "1")
        let same = try cloud(.googleDrive, account: "a", id: id, date: date, revision: "1")
        let revised = try cloud(.googleDrive, account: "a", id: id, date: date, revision: "2")
        let otherAccount = try cloud(.googleDrive, account: "b", id: id, date: date, revision: "1")
        let newDate = try cloud(.googleDrive, account: "a", id: id, date: date.addingTimeInterval(60), revision: "1")
        let changedProfile = GalleryItem(source: same.source, date: same.date,
            profile: CaptureProfileTag(id: UUID(), name: "Obra"))
        XCTAssertTrue(GalleryItem.sameCloudSnapshot([old], [same]))
        XCTAssertFalse(GalleryItem.sameCloudSnapshot([old], [revised]))
        XCTAssertFalse(GalleryItem.sameCloudSnapshot([old], [otherAccount]))
        XCTAssertFalse(GalleryItem.sameCloudSnapshot([old], [newDate]))
        XCTAssertFalse(GalleryItem.sameCloudSnapshot([old], [changedProfile]))
        XCTAssertFalse(GalleryItem.sameCloudSnapshot([old], []))
        XCTAssertFalse(GalleryItem.sameCloudSnapshot([old, otherAccount], [otherAccount, old]))
    }

    private func cloud(_ provider: CloudDeliveryPlan.Provider, account: String, id: UUID, date: Date,
                       revision: String? = nil) throws -> GalleryItem {
        let destination = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: provider,
                                         accountHash: String(repeating: account, count: 64)))
        let account = CloudArchiveAccounts.Account(id: destination, label: account, enabled: true)
        let name = CloudArchiveFilename.make(captureID: id, capturedAt: date, profile: nil, originalExtension: nil)
        let entry = CloudGalleryCatalog.Entry(id: "file-id", name: name, date: date, revision: revision)
        let item = try XCTUnwrap(GalleryCloudItem.cachedPage([entry], for: account).items.first)
        return GalleryItem(source: .cloud(item), date: date, profile: nil)
    }
}
