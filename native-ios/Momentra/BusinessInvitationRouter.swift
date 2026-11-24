import Foundation
import Combine

extension Notification.Name {
    static let businessOrganizationsDidChange = Notification.Name("photomark.business.organizations.changed")
}

@MainActor
final class BusinessInvitationRouter: ObservableObject {
    struct Invitation: Identifiable, Equatable {
        let organizationID: String
        let invitationID: String
        var id: String { organizationID + ":" + invitationID }
    }
    static let shared = BusinessInvitationRouter()
    @Published var pending: Invitation?
    private init() {}

    /// A link contains no authority by itself; the server verifies the signed-in email.
    func handle(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "momentra", parts.host?.lowercased() == "business",
              parts.path == "/invite", parts.user == nil, parts.password == nil, parts.port == nil,
              parts.fragment == nil, let items = parts.queryItems, items.count == 2,
              let org = items.first(where: { $0.name == "organization" })?.value,
              let invitation = items.first(where: { $0.name == "invitation" })?.value,
              UUID(uuidString: org) != nil, UUID(uuidString: invitation) != nil else { return false }
        pending = Invitation(organizationID: org.lowercased(), invitationID: invitation.lowercased())
        return true
    }
}
