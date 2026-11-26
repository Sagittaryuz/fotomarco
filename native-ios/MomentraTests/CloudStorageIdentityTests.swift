import XCTest
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
}
