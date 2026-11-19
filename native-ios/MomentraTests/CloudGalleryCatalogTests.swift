import XCTest
@testable import Momentra

final class CloudGalleryCatalogTests: XCTestCase {
    private let google = CloudDeliveryPlan.Destination(provider: .googleDrive, accountHash: String(repeating: "a", count: 64))!
    private let microsoft = CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: String(repeating: "a", count: 64))!
    private let secondGoogle = CloudDeliveryPlan.Destination(provider: .googleDrive, accountHash: String(repeating: "b", count: 64))!
    private let image = CloudGalleryCatalog.Entry(id: "image", name: "capture.jpg", date: nil, revision: "1")

    func testCatalogSurvivesRestartAndIsScopedToTheProviderAndAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let issued = Date(timeIntervalSince1970: 1_000_000)
        let first = CloudGalleryCatalog(directory: directory)
        let stored = await first.replace([image, image], for: google, replacing: nil, at: issued)
        XCTAssertTrue(stored)

        let restarted = CloudGalleryCatalog(directory: directory)
        let cached = await restarted.snapshot(for: google)
        XCTAssertEqual(cached?.entries, [image])
        XCTAssertEqual(cached?.needsRefresh(at: issued.addingTimeInterval(299)), false)
        XCTAssertEqual(cached?.needsRefresh(at: issued.addingTimeInterval(300)), true)
        let otherProvider = await restarted.snapshot(for: microsoft)
        let otherAccount = await restarted.snapshot(for: secondGoogle)
        XCTAssertNil(otherProvider)
        XCTAssertNil(otherAccount)
    }

    func testRemovalPersistsAndAnOlderRefreshCannotBringBackThePhoto() async {
        let catalog = CloudGalleryCatalog(directory: nil)
        let remaining = CloudGalleryCatalog.Entry(id: "kept", name: "other.jpg", date: nil, revision: nil)
        await catalog.replace([image, remaining], for: google, replacing: nil)
        let before = await catalog.snapshot(for: google)
        await catalog.invalidate(google, removing: image.id)
        let accepted = await catalog.replace([image, remaining], for: google, replacing: before?.revision)
        let after = await catalog.snapshot(for: google)
        XCTAssertFalse(accepted)
        XCTAssertEqual(after?.entries, [remaining])
        XCTAssertEqual(after?.needsRefresh(), true)
    }

    func testInvalidationDiscardsAnInitialListingThatStartedBeforeTheUpload() async {
        let catalog = CloudGalleryCatalog(directory: nil)
        await catalog.invalidate(google)
        let accepted = await catalog.replace([image], for: google, replacing: nil)
        let stale = await catalog.snapshot(for: google)
        XCTAssertFalse(accepted)
        XCTAssertEqual(stale?.needsRefresh(), true)
        let refreshed = await catalog.replace([image], for: google, replacing: stale?.revision)
        XCTAssertTrue(refreshed)
    }
}
