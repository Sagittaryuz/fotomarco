import XCTest
@testable import Momentra

private actor PhotoTransportStub: PersonalPhotoTransport {
    var uploads = 0
    var creates = 0
    var verifies = 0
    var creationFails = false
    var verifySucceeds = false

    func setCreationFails(_ value: Bool) { creationFails = value }
    func setVerifySucceeds(_ value: Bool) { verifySucceeds = value }
    func counts() -> (Int, Int, Int) { (uploads, creates, verifies) }
    func uploadBytes(_ jpeg: Data) async throws -> String { uploads += 1; return "upload-token" }
    func createItem(uploadToken: String, filename: String) async throws -> String {
        creates += 1
        if creationFails { throw URLError(.timedOut) }
        return "item_123"
    }
    func verifyItem(id: String) async throws -> Bool { verifies += 1; return verifySucceeds }
}

final class PersonalPhotoUploadTests: XCTestCase {
    private let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])

    func testConsentAndJPEGAreRequired() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PhotoTransportStub()
        let uploader = PersonalPhotoUploader(directory: root, transport: transport)
        let noConsent = await uploader.upload(jpeg: jpeg, captureID: UUID(), owner: "owner", personalConsent: false)
        let invalid = await uploader.upload(jpeg: Data([1, 2, 3]), captureID: UUID(), owner: "owner", personalConsent: true)
        XCTAssertEqual(noConsent, .failed)
        XCTAssertEqual(invalid, .failed)
        let counts = await transport.counts()
        XCTAssertEqual(counts.0, 0)
    }

    func testAmbiguousCreationNeverAutomaticallyResends() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PhotoTransportStub()
        await transport.setCreationFails(true)
        let uploader = PersonalPhotoUploader(directory: root, transport: transport)
        let id = UUID()
        let first = await uploader.upload(jpeg: jpeg, captureID: id, owner: "owner", personalConsent: true)
        let again = await uploader.upload(jpeg: jpeg, captureID: id, owner: "owner", personalConsent: true)
        XCTAssertEqual(first, .uncertain)
        XCTAssertEqual(again, .uncertain)
        let counts = await transport.counts()
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 1)
    }

    func testKnownItemRetryOnlyVerifies() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = PhotoTransportStub()
        let uploader = PersonalPhotoUploader(directory: root, transport: transport)
        let id = UUID()
        let first = await uploader.upload(jpeg: jpeg, captureID: id, owner: "owner", personalConsent: true)
        XCTAssertEqual(first, .verificationPending("item_123"))
        await transport.setVerifySucceeds(true)
        let again = await uploader.upload(jpeg: jpeg, captureID: id, owner: "owner", personalConsent: true)
        XCTAssertEqual(again, .verified("item_123"))
        let counts = await transport.counts()
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 1)
        XCTAssertEqual(counts.2, 2)
    }
}
