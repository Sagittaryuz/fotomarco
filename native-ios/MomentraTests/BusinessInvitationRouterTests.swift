import XCTest
@testable import Momentra

@MainActor
final class BusinessInvitationRouterTests: XCTestCase {
    func testOnlyWellFormedInvitationLinksAreAccepted() throws {
        let router = BusinessInvitationRouter.shared
        router.pending = nil
        let org = UUID().uuidString
        let invitation = UUID().uuidString
        XCTAssertTrue(router.handle(try XCTUnwrap(URL(string: "momentra://business/invite?organization=\(org)&invitation=\(invitation)"))))
        XCTAssertEqual(router.pending?.organizationID, org.lowercased())
        router.pending = nil
        XCTAssertFalse(router.handle(try XCTUnwrap(URL(string: "momentra://business/invite?organization=\(org)&invitation=\(invitation)&extra=x"))))
        XCTAssertFalse(router.handle(try XCTUnwrap(URL(string: "momentra://business/invite?organization=../x&invitation=\(invitation)"))))
        XCTAssertFalse(router.handle(try XCTUnwrap(URL(string: "momentra://other/invite?organization=\(org)&invitation=\(invitation)"))))
        XCTAssertNil(router.pending)
    }
}
