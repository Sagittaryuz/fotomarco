import Foundation

@MainActor final class BusinessLegacyImportCoordinator {
    static let shared = BusinessLegacyImportCoordinator()
    private var target: (organizationID: UUID, userID: String)?
    private var running = false
    private init() {}

    func configure(organizationID: UUID?, userID: String?) {
        guard let organizationID, let userID else { target = nil; return }
        target = (organizationID, userID)
    }

    func stageIfReady() async {
        guard !running, let target, BusinessIdentity.shared.userID == target.userID,
              BusinessIdentity.shared.emailVerified else { return }
        running = true
        defer { running = false }
        guard let root = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true) else { return }
        do {
            let result = try await Task.detached(priority: .utility) {
                try BusinessLegacyLocalImport.stage(root: root, organizationID: target.organizationID, userID: target.userID,
                    cutoff: Date(timeIntervalSince1970: 1_795_484_909))
            }.value
            if result.staged > 0 { CloudBackgroundScheduler.scheduleIfNeeded() }
        } catch {
            // Source and queued files remain intact; the next pass retries.
        }
    }
}
