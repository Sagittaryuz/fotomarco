import Foundation

/// Refreshes immutable organization snapshots separately from local personal profiles.
@MainActor
enum BusinessProfileSync {
    static func refresh(into store: StampProfilesStore, identity: BusinessIdentity = .shared) async {
        guard let userID = identity.userID, identity.emailVerified, let api = BusinessAPIClient.configured() else { return }
        do {
            let token = try await identity.verifiedToken()
            let organizations = try await api.myOrganizations(token: token).organizations
            var snapshots: [(organizationID: String, profile: StampProfile)] = []
            let transfer = BusinessProfileTransfer(api: api)
            for organization in organizations where organization.captureReady == true {
                guard !Task.isCancelled, identity.userID == userID else { return }
                do {
                    let profile = try await transfer.fetch(organizationID: organization.id, token: token)
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
        } catch {
            // Keep the last in-memory state if the organization list cannot be checked.
        }
    }
}
