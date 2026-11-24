import Foundation

@MainActor final class BusinessLegacyImportCoordinator {
    static let shared = BusinessLegacyImportCoordinator()
    private var target: (organizationID: UUID, userID: String)?
    private var running = false
    private struct CloudCandidate {
        let stamped: GalleryCloudItem
        var original: GalleryCloudItem?
        let date: Date
    }
    private struct RenameCandidate { let item: GalleryCloudItem; let date: Date }
    private var candidates: [CloudCandidate]?
    private var candidateIndex = 0
    private var candidateAccountIDs: [CloudDeliveryPlan.Destination] = []
    private var candidatesUpdatedAt: Date?
    private var localScanCompletedAt: Date?
    private var renameCandidates: [RenameCandidate] = []
    private var renameIndex = 0
    private init() {}

    func configure(organizationID: UUID?, userID: String?) {
        guard let organizationID, let userID else { target = nil; candidates = nil; candidateIndex = 0; renameCandidates = []; renameIndex = 0; localScanCompletedAt = nil; return }
        if target?.organizationID != organizationID || target?.userID != userID { candidates = nil; candidateIndex = 0; renameCandidates = []; renameIndex = 0; localScanCompletedAt = nil }
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
            if let lastScan = localScanCompletedAt, Date().timeIntervalSince(lastScan) < 300 {
                try await stageOneCloudCapture(root: root, target: target)
                await renameOneCloudCapture(target: target)
                return
            }
            let result = try await Task.detached(priority: .utility) {
                try BusinessLegacyLocalImport.stage(root: root, organizationID: target.organizationID, userID: target.userID,
                    cutoff: Date(timeIntervalSince1970: 1_795_484_909))
            }.value
            if result.staged > 0 { CloudBackgroundScheduler.scheduleIfNeeded() }
            guard BusinessIdentity.shared.userID == target.userID, self.target?.organizationID == target.organizationID, !Task.isCancelled else { return }
            if result.staged == 0 && !result.more {
                localScanCompletedAt = .now
                try await stageOneCloudCapture(root: root, target: target)
                await renameOneCloudCapture(target: target)
            }
        } catch {
            // Source and queued files remain intact; the next pass retries.
        }
    }

    private func stageOneCloudCapture(root: URL, target: (organizationID: UUID, userID: String)) async throws {
        let journal = BusinessArchiveJournal(root: root)
        let ids = try journal.ids()
        let pending = try ids.reduce(0) { $0 + ((try journal.read($1)).finished ? 0 : 1) }
        let free = ((try? FileManager.default.attributesOfFileSystem(forPath: root.path))?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free > 1_000_000_000 else { return }
        let accounts = CloudArchiveAccounts.shared.accounts
        let accountIDs = accounts.map(\.id)
        let rescan = candidates.map { candidateIndex >= $0.count } == true &&
            candidatesUpdatedAt.map { Date().timeIntervalSince($0) >= 300 } == true
        if candidates == nil || candidateAccountIDs != accountIDs || rescan {
            let dates = await Task.detached(priority: .utility) { PhotoProfileIndex.load(root: root).dates }.value
            var stamped: [UUID: GalleryCloudItem] = [:], originals: [UUID: GalleryCloudItem] = [:], knownDates: [UUID: Date] = [:]
            var pendingRenames: [RenameCandidate] = []
            let cutoff = Date(timeIntervalSince1970: 1_795_484_909)
            for account in accounts {
                var page: GalleryCloudItem.Page?, cursor: String?, seen = Set<String>(), pages = 0
                repeat {
                    guard !Task.isCancelled, BusinessIdentity.shared.userID == target.userID,
                          self.target?.organizationID == target.organizationID else { return }
                    let next = try await GalleryCloudItem.load(for: account, pageToken: cursor, reusing: page)
                    pages += 1
                    guard pages <= 1000 else { throw CocoaError(.fileReadCorruptFile) }
                    for item in next.items {
                        guard let date = dates[item.captureID] ?? CloudArchiveFilename(item.name)?.capturedAt ?? item.providerCaptureDate, date <= cutoff else { continue }
                        if let renamed = CloudArchiveFilename.renamed(item.name, provider: item.provider, timeZone: .current, knownCaptureDate: date), renamed != item.name {
                            pendingRenames.append(RenameCandidate(item: item, date: date))
                        }
                        if item.isOriginal { if originals[item.captureID] == nil { originals[item.captureID] = item } }
                        else if stamped[item.captureID] == nil { stamped[item.captureID] = item; knownDates[item.captureID] = date }
                    }
                    page = next
                    cursor = next.nextPage
                    if let cursor, !seen.insert(cursor).inserted { throw CocoaError(.fileReadCorruptFile) }
                } while cursor != nil
            }
            candidates = stamped.compactMap { id, item in
                knownDates[id].map { CloudCandidate(stamped: item, original: originals[id], date: $0) }
            }.sorted { $0.date < $1.date }
            candidateIndex = 0
            renameCandidates = pendingRenames
            renameIndex = 0
            candidateAccountIDs = accountIDs
            candidatesUpdatedAt = .now
        }
        guard let candidates else { return }
        let alreadyQueued = Set(ids)
        while candidateIndex < candidates.count {
            let candidate = candidates[candidateIndex]
            var needsOriginal = candidate.original != nil
            if alreadyQueued.contains(candidate.stamped.captureID) {
                let queued = try journal.read(candidate.stamped.captureID)
                if queued.ready || queued.organizationID != target.organizationID || queued.userID != target.userID || queued.createdAt != candidate.date {
                    candidateIndex += 1; continue
                }
                needsOriginal = queued.keepsOriginal
                if needsOriginal && candidate.original == nil { throw CocoaError(.fileNoSuchFile) }
            } else if pending >= 3 { return }
            guard !Task.isCancelled, BusinessIdentity.shared.userID == target.userID,
                  self.target?.organizationID == target.organizationID else { return }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let stampDirectory = directory.appendingPathComponent("stamped", isDirectory: true)
            let originalDirectory = directory.appendingPathComponent("original", isDirectory: true)
            try FileManager.default.createDirectory(at: stampDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
            let stampFile = try await candidate.stamped.copy(to: stampDirectory)
            var originalFile: URL?
            if needsOriginal, let original = candidate.original { originalFile = try await original.copy(to: originalDirectory) }
            guard !Task.isCancelled, BusinessIdentity.shared.userID == target.userID,
                  self.target?.organizationID == target.organizationID else { return }
            let captureID = candidate.stamped.captureID, date = candidate.date, cutoff = Date(timeIntervalSince1970: 1_795_484_909)
            try await Task.detached(priority: .utility) {
                try PhotoProfileIndex.associateLegacyCapture(captureID, captureDate: date, organizationID: target.organizationID,
                    name: "JMD Hamoa", before: cutoff, root: root)
                try BusinessLegacyCloudStage.stage(root: root, stamped: stampFile, original: originalFile, captureID: captureID,
                    date: date, organizationID: target.organizationID, userID: target.userID, cutoff: cutoff)
            }.value
            candidateIndex += 1
            CloudBackgroundScheduler.scheduleIfNeeded()
            return
        }
    }

    private func renameOneCloudCapture(target: (organizationID: UUID, userID: String)) async {
        guard renameIndex < renameCandidates.count, !Task.isCancelled,
              BusinessIdentity.shared.userID == target.userID, self.target?.organizationID == target.organizationID else { return }
        let candidate = renameCandidates[renameIndex]
        // A provider conflict or transient failure never stops the remaining import.
        // The next complete scan retries items whose names still need updating.
        renameIndex += 1
        try? await candidate.item.renameForCaptureDate(candidate.date)
    }
}
