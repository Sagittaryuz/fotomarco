import Foundation

/// Refreshes immutable organization snapshots separately from local personal profiles.
@MainActor
enum BusinessProfileSync {
    static func refresh(into store: StampProfilesStore, identity: BusinessIdentity = .shared) async {
        guard let userID = identity.userID, identity.emailVerified, let api = BusinessAPIClient.configured() else { return }
        do {
            let token = try await identity.verifiedToken()
            var ownerOrganizationID: String?
            if identity.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mrpires72@gmail.com" {
                ownerOrganizationID = try await api.ensureOwnerOrganization(token: token).organizationId
                if let ownerOrganizationID, let orgID = UUID(uuidString: ownerOrganizationID) {
                    // User requested the historical association on 23 Nov 2026 (São Paulo).
                    // The cutoff prevents captures subsequently made in Pessoal from being reassigned.
                    _ = try await Task.detached(priority: .utility) {
                        try PhotoProfileIndex.associateLegacyCaptures(organizationID: orgID, name: "JMD Hamoa",
                            before: Date(timeIntervalSince1970: 1_795_484_909))
                    }.value
                    guard !Task.isCancelled, identity.userID == userID else { return }
                }
            }
            let organizations = try await api.myOrganizations(token: token).organizations
            var snapshots: [(organizationID: String, profile: StampProfile)] = []
            let transfer = BusinessProfileTransfer(api: api)
            if let id = ownerOrganizationID, let ownerOrg = organizations.first(where: { $0.id == id && $0.role == "owner" }), ownerOrg.profileReady == false {
                let candidate = store.profiles.first(where: { $0.name.localizedCaseInsensitiveContains("hamoa") }) ??
                    store.profiles.first(where: { $0.id == store.selectedID && $0.name.localizedCaseInsensitiveCompare("Pessoal") != .orderedSame }) ??
                    store.profiles.first(where: { $0.name.localizedCaseInsensitiveCompare("Pessoal") != .orderedSame })
                if let candidate { _ = try await transfer.publish(candidate, organizationID: id, token: token, onlyIfAbsent: true) }
            }
            for organization in organizations where organization.captureReady == true {
                guard !Task.isCancelled, identity.userID == userID else { return }
                do {
                    var profile = try await transfer.fetch(organizationID: organization.id, token: token)
                    profile.name = organization.name
                    snapshots.append((organization.id, profile))
                } catch BusinessAPIClient.Failure.unauthorized {
                    // A denied profile is not retained as an active organization selection.
                } catch {
                    // Preserve an already loaded snapshot across a transient network error.
                    if let id = UUID(uuidString: organization.id),
                       let cached = store.organizationProfiles.first(where: { $0.id == id }) {
                        snapshots.append((organization.id, cached))
                    }
                }
            }
            guard !Task.isCancelled, identity.userID == userID, identity.emailVerified else { return }
            store.replaceOrganizationProfiles(snapshots)
            let ownerID = ownerOrganizationID.flatMap(UUID.init(uuidString:))
            let ready = ownerID.map { id in snapshots.contains(where: { UUID(uuidString: $0.organizationID) == id }) } ?? false
            BusinessLegacyImportCoordinator.shared.configure(organizationID: ready ? ownerID : nil, userID: ready ? userID : nil)
        } catch {
            // Keep the last in-memory state if the organization list cannot be checked.
        }
    }
}
