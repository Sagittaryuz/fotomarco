import XCTest
import CryptoKit
@testable import Momentra

final class CloudStorageIdentityTests: XCTestCase {
    func testMatchesServerAndIsScopedToTheUser() throws {
        let first = try XCTUnwrap(CloudStorageIdentity.fingerprint(provider: .oneDrive, canonicalID: "drive-A", userID: "user-A"))
        XCTAssertEqual(first, "dec8d46104fcfc5f754c8e94a8afcc5e7d029f413995c47e924270686f8a0234")
        let other = CloudStorageIdentity.fingerprint(provider: .oneDrive, canonicalID: "drive-A", userID: "user-B")
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(CloudStorageIdentity.compare(first, first), .same)
        XCTAssertEqual(CloudStorageIdentity.compare(first, other), .different)
        XCTAssertEqual(CloudStorageIdentity.compare(first, nil), .unknown)
        XCTAssertNil(CloudStorageIdentity.fingerprint(provider: .oneDrive, canonicalID: "", userID: "user-A"))
    }

    func testRejectsPersonalAccountWhenProviderBindingsDoNotMatch() throws {
        let binding = "7:subjectdrive-A"
        let hash = SHA256.hash(data: Data(binding.utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = try XCTUnwrap(CloudDeliveryPlan.Destination(provider: .oneDrive, accountHash: hash))
        let result = CloudStorageIdentity.verifiedFingerprint(destination: destination, canonicalID: "drive-A", userID: "user-A", bindings: [binding])
        XCTAssertEqual(result, "dec8d46104fcfc5f754c8e94a8afcc5e7d029f413995c47e924270686f8a0234")
        XCTAssertNil(CloudStorageIdentity.verifiedFingerprint(destination: destination, canonicalID: "drive-B", userID: "user-A", bindings: ["7:subjectdrive-B"]))
    }
}
