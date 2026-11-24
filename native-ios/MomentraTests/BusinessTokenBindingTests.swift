import XCTest
@testable import Momentra

@MainActor final class BusinessTokenBindingTests: XCTestCase {
    func testRejectsAccountSwitchDuringTokenRequest() async throws {
        var current: String? = "owner"
        do {
            _ = try await BusinessTokenBinding.acquire(expectedUserID: "owner", currentUserID: { current }) {
                current = "other"
                return "test-token"
            }
            XCTFail("A token must not be returned after an account switch")
        } catch BusinessIdentity.IdentityError.signedOut {
            XCTAssertEqual(current, "other")
        }
    }

    func testDoesNotRequestTokenForAnotherAccount() async throws {
        var requested = false
        do {
            _ = try await BusinessTokenBinding.acquire(expectedUserID: "owner", currentUserID: { "other" }) {
                requested = true
                return "test-token"
            }
            XCTFail("A different user must not receive the capture owner's token")
        } catch BusinessIdentity.IdentityError.signedOut {
            XCTAssertFalse(requested)
        }
    }
}
