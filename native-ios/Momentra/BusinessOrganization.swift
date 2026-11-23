import Foundation

/// Domain rules for an organization. The server must independently enforce every rule.
enum OrganizationRole: String, Codable, Equatable {
    case owner, administrator, member

    var managesOrganization: Bool { self == .owner || self == .administrator }
}

struct OrganizationMembership: Codable, Equatable {
    let organizationID: UUID
    let userID: UUID
    let role: OrganizationRole
    let active: Bool
}

struct BusinessOrganization: Codable, Equatable {
    static let maximumMembers = 500
    let id: UUID
    let ownerID: UUID
    let name: String

    func mayManage(_ membership: OrganizationMembership) -> Bool {
        guard membership.active, membership.organizationID == id else { return false }
        if membership.role == .owner { return membership.userID == ownerID }
        return membership.role == .administrator
    }

    func mayUsePublishedProfile(_ membership: OrganizationMembership) -> Bool {
        membership.active && membership.organizationID == id &&
            (membership.role != .owner || membership.userID == ownerID)
    }

    func mayViewPhoto(takenBy authorID: UUID, organizationID: UUID,
                      membership: OrganizationMembership) -> Bool {
        guard organizationID == id, mayUsePublishedProfile(membership) else { return false }
        return mayManage(membership) || membership.userID == authorID
    }

    func mayInvite(_ membership: OrganizationMembership, activeMembers: Int) -> Bool {
        mayManage(membership) && activeMembers >= 0 && activeMembers < Self.maximumMembers
    }
}

/// Components are names only: existing folders are never moved or renamed.
enum OrganizationFolderNaming {
    static func memberFolder(name: String, email: String) -> String? {
        let unsafe = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        func clean(_ value: String) -> String {
            value.components(separatedBy: unsafe).joined(separator: " ")
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        let display = clean(name)
        let address = clean(email)
        guard !display.isEmpty, address.contains("@"), address.count <= 254,
              !address.contains(" "), address != ".", address != ".." else { return nil }
        let result = "\(display) (\(address))"
        guard result.utf8.count <= 240 else { return nil }
        return result
    }
}
