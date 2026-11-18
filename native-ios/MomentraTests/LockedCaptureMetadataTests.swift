import XCTest
@testable import Momentra

@available(iOS 18.0, *)
final class LockedCaptureMetadataTests: XCTestCase {
    @MainActor
    func testCaptureIntentRequestsCameraWhenAppIsAlreadyOpen() async throws {
        let received = expectation(description: "Pedido para abrir câmera")
        let token = NotificationCenter.default.addObserver(forName: .momentraOpenCamera, object: nil, queue: nil) { _ in
            received.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        _ = try await MomentraCaptureIntent().perform()
        await fulfillment(of: [received], timeout: 1)
    }

    func testLegacyContextStillDecodesWithoutNewFields() throws {
        let context = MomentraCaptureContext(stampEnabled: true, gpsEnabled: false, title: "perfil antigo",
            note: "", compact: false, position: "bottom", horizontal: "auto", longDate: false,
            fontStyle: "system", aspect: "4:3", saveToPhotos: true,
            profileID: UUID(), profileName: "Padrão", cloudOwnerHash: CloudCaptureQueue.ownerHash("person-a"))
        let encoded = try JSONEncoder().encode(context)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "profileID")
        object.removeValue(forKey: "profileName")
        object.removeValue(forKey: "cloudOwnerHash")
        object.removeValue(forKey: "layoutData")
        object.removeValue(forKey: "hasLogo")
        let legacy = try JSONDecoder().decode(MomentraCaptureContext.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.profileID)
        XCTAssertNil(legacy.profileName)
        XCTAssertNil(legacy.cloudOwnerHash)
        XCTAssertNil(legacy.layoutData)
        XCTAssertNil(legacy.hasLogo)
    }

    func testLayoutFitsAndRoundTripsThroughCaptureContext() throws {
        var layout = StampLayout()
        layout.mode = .separate
        layout.informationSize = 1.5
        let layoutData = try JSONEncoder().encode(layout)
        XCTAssertLessThanOrEqual(layoutData.count, 2000)
        let context = MomentraCaptureContext(stampEnabled: true, gpsEnabled: false, title: "", note: "",
            compact: false, position: "bottom", horizontal: "auto", longDate: false, fontStyle: "system",
            aspect: "4:3", saveToPhotos: false, profileID: UUID(), profileName: "Padrão",
            cloudOwnerHash: CloudCaptureQueue.ownerHash("person-a"), layoutData: layoutData)
        let encoded = try JSONEncoder().encode(context)
        XCTAssertLessThan(encoded.count, 4096)
        let decoded = try JSONDecoder().decode(MomentraCaptureContext.self, from: encoded)
        let recovered = try JSONDecoder().decode(StampLayout.self, from: XCTUnwrap(decoded.layoutData))
        XCTAssertEqual(recovered.mode, .separate)
        XCTAssertEqual(recovered.informationSize, 1.5)
    }

    func testMetadataRejectsInvalidAccountAndBoundsProfileName() {
        let id = UUID()
        let longName = String(repeating: "👨‍👩‍👧‍👦", count: 80)
        let safeName = LockedCaptureMetadata.safeProfileName(longName)
        XCTAssertLessThanOrEqual(safeName.utf8.count, 240)
        let invalid = LockedCaptureMetadata(captureID: id, capturedAt: Date(), profileID: UUID(),
                                            profileName: safeName, cloudOwnerHash: "invalid")
        XCTAssertFalse(invalid.isValid(for: id))
    }

    func testLockedCaptureIsBoundToProfileAndMatchingCloudAccount() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let session = base.appendingPathComponent("session"), root = base.appendingPathComponent("app")
        let id = UUID(), profileID = UUID(), hash = CloudCaptureQueue.ownerHash("person-a")
        let sourceProcessed = session.appendingPathComponent("Processed")
        let metadataDir = session.appendingPathComponent("Metadata")
        try FileManager.default.createDirectory(at: sourceProcessed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadataDir, withIntermediateDirectories: true)
        let name = id.uuidString + ".jpg"
        try Data("original".utf8).write(to: session.appendingPathComponent(name))
        try Data("stamped".utf8).write(to: sourceProcessed.appendingPathComponent(name))
        let metadata = LockedCaptureMetadata(captureID: id, capturedAt: Date(timeIntervalSince1970: 1000),
                                             profileID: profileID, profileName: "Obra", cloudOwnerHash: hash)
        try JSONEncoder().encode(metadata).write(to: metadataDir.appendingPathComponent(id.uuidString + ".json"))
        LockedCaptureImporter.copyFiles(from: session, to: root.appendingPathComponent("Originals"))
        LockedCaptureImporter.copyFiles(from: sourceProcessed, to: root.appendingPathComponent("Processed"))
        let result = LockedCaptureImporter.importMetadata(from: session, to: root, allowedCloudOwnerHash: hash)
        XCTAssertEqual(result, 1)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        XCTAssertEqual(try queue.entry(id: id).phase, .ready)
        XCTAssertEqual(PhotoProfileIndex.load(root: root).captures[id]?.id, profileID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.appendingPathComponent(name).path))
        XCTAssertTrue(LockedCaptureImporter.sessionIsSafelyImported(session, root: root, allowedCloudOwnerHash: hash))
        let unexpected = session.appendingPathComponent("unrecognized.dat")
        try Data("keep".utf8).write(to: unexpected)
        XCTAssertFalse(LockedCaptureImporter.sessionIsSafelyImported(session, root: root, allowedCloudOwnerHash: hash))
        try FileManager.default.removeItem(at: unexpected)
        XCTAssertEqual(LockedCaptureImporter.importMetadata(from: session, to: root, allowedCloudOwnerHash: hash), 1)
        XCTAssertEqual(try queue.entries(ownerHash: hash).count, 1)
    }

    func testMismatchedCopyOrAccountCannotQueueForCloud() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let session = base.appendingPathComponent("session"), root = base.appendingPathComponent("app")
        let id = UUID(), owner = CloudCaptureQueue.ownerHash("person-a")
        let sourceProcessed = session.appendingPathComponent("Processed")
        let metadataDir = session.appendingPathComponent("Metadata")
        try FileManager.default.createDirectory(at: sourceProcessed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadataDir, withIntermediateDirectories: true)
        let name = id.uuidString + ".jpg"
        try Data("original".utf8).write(to: session.appendingPathComponent(name))
        try Data("stamped".utf8).write(to: sourceProcessed.appendingPathComponent(name))
        let metadata = LockedCaptureMetadata(captureID: id, capturedAt: Date(), profileID: UUID(),
                                             profileName: "Padrão", cloudOwnerHash: owner)
        try JSONEncoder().encode(metadata).write(to: metadataDir.appendingPathComponent(id.uuidString + ".json"))
        LockedCaptureImporter.copyFiles(from: session, to: root.appendingPathComponent("Originals"))
        LockedCaptureImporter.copyFiles(from: sourceProcessed, to: root.appendingPathComponent("Processed"))
        XCTAssertEqual(LockedCaptureImporter.importMetadata(from: session, to: root,
                       allowedCloudOwnerHash: CloudCaptureQueue.ownerHash("person-b")), 0)
        try Data("changed".utf8).write(to: root.appendingPathComponent("Originals").appendingPathComponent(name))
        XCTAssertFalse(LockedCaptureImporter.sessionIsSafelyImported(session, root: root, allowedCloudOwnerHash: owner))
        XCTAssertEqual(LockedCaptureImporter.importMetadata(from: session, to: root, allowedCloudOwnerHash: owner), 0)
        XCTAssertTrue(try CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending")).entries(ownerHash: owner).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.appendingPathComponent(name).path))
    }
    func testCleanedCloudCaptureIsNotReimportedFromLockedSession() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let session = base.appendingPathComponent("session"), root = base.appendingPathComponent("app")
        let id = UUID(), owner = "person-a", name = id.uuidString + ".jpg"
        let processed = session.appendingPathComponent("Processed")
        try FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: session.appendingPathComponent(name))
        try Data("stamped".utf8).write(to: processed.appendingPathComponent(name))
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        let originalsDir = root.appendingPathComponent("Originals"), processedDir = root.appendingPathComponent("Processed")
        LockedCaptureImporter.copyFiles(from: session, to: originalsDir, cloudQueue: queue)
        LockedCaptureImporter.copyFiles(from: processed, to: processedDir, cloudQueue: queue)
        let localOriginal = originalsDir.appendingPathComponent(name), localStamped = processedDir.appendingPathComponent(name)
        try queue.enqueue(id: id, owner: owner, originalExtension: "jpg")
        try queue.markReady(id: id, original: localOriginal, processed: localStamped)
        try queue.markVerified(id: id, originalMediaID: "original-id", processedMediaID: "stamped-id")
        try queue.beginCleanup(id: id, owner: owner)
        try FileManager.default.removeItem(at: localOriginal)
        LockedCaptureImporter.copyFiles(from: session, to: originalsDir, cloudQueue: queue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localOriginal.path))
        try FileManager.default.removeItem(at: localStamped)
        try queue.finishCleanup(id: id, owner: owner)
        LockedCaptureImporter.copyFiles(from: session, to: originalsDir, cloudQueue: queue)
        LockedCaptureImporter.copyFiles(from: processed, to: processedDir, cloudQueue: queue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localOriginal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: localStamped.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.appendingPathComponent(name).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: processed.appendingPathComponent(name).path))
    }

}
