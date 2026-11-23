import XCTest
@testable import Momentra

final class BusinessOrganizationTests: XCTestCase {
    private let org = UUID(), owner = UUID(), member = UUID()
    private var organization: BusinessOrganization { .init(id: org, ownerID: owner, name: "Equipe") }
    private func membership(_ user: UUID, _ role: OrganizationRole, active: Bool = true,
                            orgID: UUID? = nil) -> OrganizationMembership {
        .init(organizationID: orgID ?? org, userID: user, role: role, active: active)
    }

    func testOwnerCanManageAndSeeTeamButMemberOnlyOwnPhotos() {
        let administrator = membership(owner, .owner)
        let user = membership(member, .member)
        XCTAssertTrue(organization.mayManage(administrator))
        XCTAssertTrue(organization.mayViewPhoto(takenBy: member, organizationID: org, membership: administrator))
        XCTAssertFalse(organization.mayManage(user))
        XCTAssertTrue(organization.mayViewPhoto(takenBy: member, organizationID: org, membership: user))
        XCTAssertFalse(organization.mayViewPhoto(takenBy: owner, organizationID: org, membership: user))
    }

    func testRevokedAndOtherOrganizationHaveNoAccess() {
        XCTAssertFalse(organization.mayUsePublishedProfile(membership(member, .member, active: false)))
        XCTAssertFalse(organization.mayViewPhoto(takenBy: member, organizationID: org, membership: membership(member, .member, orgID: UUID())))
        XCTAssertFalse(organization.mayManage(membership(member, .owner)))
        XCTAssertFalse(organization.mayViewPhoto(takenBy: member, organizationID: UUID(), membership: membership(owner, .owner)))
    }

    func testFiveHundredMemberLimitIncludesOwner() {
        let admin = membership(owner, .owner)
        XCTAssertTrue(organization.mayInvite(admin, activeMembers: 499))
        XCTAssertFalse(organization.mayInvite(admin, activeMembers: 500))
        XCTAssertFalse(organization.mayInvite(admin, activeMembers: -1))
        XCTAssertFalse(organization.mayInvite(membership(member, .member), activeMembers: 1))
    }

    func testFolderComponentDoesNotAllowSeparators() {
        let value = OrganizationFolderNaming.memberFolder(name: "Ana / Silva", email: "ana@example.com")
        XCTAssertEqual(value, "Ana Silva (ana@example.com)")
        XCTAssertFalse(value?.contains("/") ?? true)
        XCTAssertNil(OrganizationFolderNaming.memberFolder(name: "", email: "ana@example.com"))
        XCTAssertNil(OrganizationFolderNaming.memberFolder(name: "Ana", email: "invalid"))
    }
}
