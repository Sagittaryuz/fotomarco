import XCTest
@testable import Momentra

final class BusinessArchiveDeliveryTests: XCTestCase {
    func testUploadChunkSizeIsCompatibleWithBothProviders() {
        let size = BusinessArchiveDelivery.chunkSize
        XCTAssertEqual(size % (320 * 1024), 0)
        XCTAssertEqual(size % (256 * 1024), 0)
        XCTAssertLessThanOrEqual(size, 320 * 1024 * 10)
    }
    func testDeliveryWaitsForVerificationAndKeepsLocalCopyOnFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.heic"), processed = root.appendingPathComponent("processed.jpg")
        try Data([1, 2, 3]).write(to: original)
        let image = Data([4, 5, 6, 7]); try image.write(to: processed)
        let id = UUID(), organization = UUID()
        let journal = BusinessArchiveJournal(root: root)
        try journal.enqueue(id: id, date: Date(timeIntervalSince1970: 1_795_470_002), originalExtension: "heic", source: original,
            target: BusinessCaptureTarget(organizationID: organization, userID: "user", keepsOriginal: false),
            profile: CaptureProfileTag(id: organization, name: "Equipe"))
        try journal.markReady(id: id, stampedSource: processed)
        let item = try journal.read(id), fingerprint = try XCTUnwrap(item.stamped)
        let client = try BusinessAPIClient(endpoint: XCTUnwrap(URL(string: "https://business.example"))) { request in
            let path = try XCTUnwrap(request.url?.path)
            let status = path.hasSuffix("/verify") ? 503 : 200
            let body: String
            if path.hasSuffix("/reserve") { body = "{\"captureId\":\"\(id.uuidString)\",\"variant\":\"stamped\",\"state\":\"reserved\"}" }
            else if path.hasSuffix("/start") { body = #"{"state":"uploading","nextOffset":0}"# }
            else if path.hasSuffix("/chunk") {
                XCTAssertEqual(request.httpBody, image)
                body = #"{"state":"verifying","nextOffset":4}"#
            } else { body = #"{"error":"unavailable"}"# }
            let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil))
            return (Data(body.utf8), response)
        }
        do {
            try await BusinessArchiveDelivery(requireUser: { userID in
                guard userID == "user" else { throw BusinessIdentity.IdentityError.signedOut }
            }).send(item, variant: "stamped", filename: item.stampedName,
                file: journal.stampedURL(item), fingerprint: fingerprint, base: 0, total: fingerprint.byteCount, api: client, token: "token")
            XCTFail("An unverified upload must not be accepted")
        } catch BusinessAPIClient.Failure.unavailable { } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(try journal.read(id).stampedVerified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.stampedURL(item).path))
        // The session changes after the upload starts; no chunk may be sent.
        let guardState = SessionGuard()
        do {
            try await BusinessArchiveDelivery(requireUser: { id in try await guardState.check(id) }).send(
                item, variant: "stamped", filename: item.stampedName, file: journal.stampedURL(item),
                fingerprint: fingerprint, base: 0, total: fingerprint.byteCount, api: client, token: "token")
            XCTFail("The upload must stop when the session changes")
        } catch BusinessIdentity.IdentityError.signedOut { } catch { XCTFail("Unexpected error: \(error)") }
        let checks = await guardState.checkCount()
        XCTAssertEqual(checks, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.stampedURL(item).path))
    }
}

private actor SessionGuard {
    private var calls = 0
    func check(_ id: String) throws {
        calls += 1
        guard id == "user", calls < 3 else { throw BusinessIdentity.IdentityError.signedOut }
    }
    func checkCount() -> Int { calls }
}
