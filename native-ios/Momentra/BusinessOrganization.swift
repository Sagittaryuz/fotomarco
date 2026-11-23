import Foundation

/// Domain rules for an organization. The server must independently enforce every rule.
enum OrganizationRole: String, Codable, Equatable {
    case owner, administrator, member

    var managesOrganization: Bool { self == .owner || self == .administrator }
}

struct OrganizationMembership: Codable, Equatable {
    let organizationID: UUID
    /// Firebase Authentication UIDs are opaque strings, not UUIDs.
    let userID: String
    let role: OrganizationRole
    let active: Bool
}

/// Presentation policy only. The service and storage provider must enforce it separately.
enum OrganizationPhotoAction: String, Codable, CaseIterable {
    case view, edit, delete, move, download
}

enum OrganizationPhotoScope: String, Codable {
    case none, own, all
}

struct OrganizationPhotoPermissions: Codable, Equatable {
    var view: OrganizationPhotoScope = .own
    var edit: OrganizationPhotoScope = .own
    var delete: OrganizationPhotoScope = .own
    var move: OrganizationPhotoScope = .own
    var download: OrganizationPhotoScope = .own

    func scope(for action: OrganizationPhotoAction) -> OrganizationPhotoScope {
        switch action {
        case .view: return view
        case .edit: return edit
        case .delete: return delete
        case .move: return move
        case .download: return download
        }
    }
}

/// Organization contact details do not establish cloud access or email-sender authority.
struct OrganizationDetails: Codable, Equatable {
    let name: String
    let contactEmail: String
    /// An opaque, access-controlled storage reference; never a public URL or access token.
    let photoReference: String?

    init?(name: String, contactEmail: String, photoReference: String? = nil) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalizedEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard !normalizedName.isEmpty, normalizedName.utf8.count <= 160,
              parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              normalizedEmail.utf8.count <= 254,
              !normalizedEmail.contains(where: { $0.isWhitespace || $0.isNewline }),
              photoReference.map({ reference in
                  !reference.isEmpty && reference.utf8.count <= 256 &&
                  !reference.contains("://") && !reference.contains("?") && !reference.contains("#")
              }) ?? true else { return nil }
        self.name = normalizedName
        self.contactEmail = normalizedEmail
        self.photoReference = photoReference
    }
}

struct BusinessOrganization: Codable, Equatable {
    static let maximumMembers = 500
    let id: UUID
    let ownerID: String
    let name: String

    func mayManage(_ membership: OrganizationMembership) -> Bool {
        guard !membership.userID.isEmpty, !ownerID.isEmpty, membership.active, membership.organizationID == id else { return false }
        if membership.role == .owner { return membership.userID == ownerID }
        return membership.role == .administrator
    }

    func mayUsePublishedProfile(_ membership: OrganizationMembership) -> Bool {
        !membership.userID.isEmpty && !ownerID.isEmpty && membership.active && membership.organizationID == id &&
            (membership.role != .owner || membership.userID == ownerID)
    }

    func mayViewPhoto(takenBy authorID: String, organizationID: UUID,
                      membership: OrganizationMembership) -> Bool {
        mayPerform(.view, takenBy: authorID, organizationID: organizationID,
                   membership: membership, permissions: .init())
    }

    func mayPerform(_ action: OrganizationPhotoAction, takenBy authorID: String,
                    organizationID: UUID, membership: OrganizationMembership,
                    permissions: OrganizationPhotoPermissions) -> Bool {
        guard organizationID == id, mayUsePublishedProfile(membership) else { return false }
        if mayManage(membership) { return true }
        switch permissions.scope(for: action) {
        case .none: return false
        case .own: return membership.userID == authorID
        case .all: return true
        }
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
