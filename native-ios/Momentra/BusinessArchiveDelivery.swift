import Foundation

/// Resumes a private team queue without changing personal storage accounts.
actor BusinessArchiveDelivery {
    static let shared = BusinessArchiveDelivery()
    struct Summary { var pending = 0; var needsAttention = false }
    private var running = false
    private let chunkSize = 320 * 1024 * 10

    func drain() async -> Summary? {
        guard !running else { return nil }
        running = true
        defer { running = false }
        var summary = Summary()
        do {
            let journal = try BusinessArchiveJournal.documents()
            var captures: [BusinessArchiveJournal.Capture] = []
            var pendingIDs = Set<UUID>()
            for id in try journal.ids() {
                do {
                    let capture = try journal.read(id)
                    if !capture.finished { captures.append(capture); pendingIDs.insert(id) }
                } catch {
                    pendingIDs.insert(id); summary.pending += 1; summary.needsAttention = true
                }
            }
            captures.sort { $0.createdAt < $1.createdAt }
            let idsToDisplay = pendingIDs
            await MainActor.run { CloudUploadProgress.shared.prepareBusinessPending(idsToDisplay) }
            let currentUser = await MainActor.run { BusinessIdentity.shared.userID }
            for item in captures {
                guard item.userID == currentUser, item.ready, let api = BusinessAPIClient.configured() else {
                    summary.pending += 1; continue
                }
                do {
                    try Task.checkCancellation()
                    let token = try await BusinessIdentity.shared.verifiedToken()
                    await MainActor.run { CloudUploadProgress.shared.start(item.id) }
                    try await deliver(item, journal: journal, api: api, token: token)
                    await MainActor.run { CloudUploadProgress.shared.finish(item.id) }
                } catch {
                    await MainActor.run { CloudUploadProgress.shared.stop(item.id) }
                    summary.pending += 1
                    if (error as? URLError)?.code != .notConnectedToInternet { summary.needsAttention = true }
                }
            }
        } catch { summary.needsAttention = true }
        return summary
    }

    private func deliver(_ item: BusinessArchiveJournal.Capture, journal: BusinessArchiveJournal,
                         api: BusinessAPIClient, token: String) async throws {
        guard let stamped = item.stamped else { throw CocoaError(.fileReadCorruptFile) }
        let originalSize = item.keepsOriginal ? (item.original?.byteCount ?? 0) : 0
        let total = max(1, originalSize + stamped.byteCount)
        if item.keepsOriginal, !item.originalVerified {
            guard let original = item.original else { throw CocoaError(.fileReadCorruptFile) }
            try await send(item, variant: "original", filename: item.originalName, file: journal.originalURL(item),
                           fingerprint: original, base: 0, total: total, api: api, token: token)
            try journal.markVerified(item.id, variant: "original")
        }
        if !item.stampedVerified {
            try await send(item, variant: "stamped", filename: item.stampedName, file: journal.stampedURL(item),
                           fingerprint: stamped, base: originalSize, total: total, api: api, token: token)
            try journal.markVerified(item.id, variant: "stamped")
        }
    }

    func send(_ item: BusinessArchiveJournal.Capture, variant: String, filename: String, file: URL,
                      fingerprint: CloudFileFingerprint, base: Int64, total: Int64,
                      api: BusinessAPIClient, token: String) async throws {
        guard try CloudFileFingerprint.read(file) == fingerprint else { throw CocoaError(.fileReadCorruptFile) }
        let org = item.organizationID.uuidString.lowercased()
        let reservation = try await api.reserveCapture(organizationID: org, captureID: item.id, filename: filename,
                                                       fingerprint: fingerprint, token: token)
        guard reservation.captureId.lowercased() == item.id.uuidString.lowercased(), reservation.variant == variant else { throw BusinessAPIClient.Failure.invalidResponse }
        if reservation.state == "verified" { return }
        var status: BusinessAPIClient.UploadStart
        switch reservation.state {
        case "reserved", "uploading": status = try await api.startCaptureUpload(organizationID: org, captureID: item.id, variant: variant, token: token)
        case "verifying": status = .init(state: "verifying", nextOffset: fingerprint.byteCount)
        default: throw BusinessAPIClient.Failure.unavailable
        }
        if status.state == "uncertain" {
            status = try await api.reconcileCapture(organizationID: org, captureID: item.id, variant: variant, token: token)
            if status.state == "reserved" {
                status = try await api.startCaptureUpload(organizationID: org, captureID: item.id, variant: variant, token: token)
            }
        }
        let fileHandle = try FileHandle(forReadingFrom: file)
        defer { try? fileHandle.close() }
        while status.state == "uploading" {
            try Task.checkCancellation()
            let offset = status.nextOffset
            guard offset >= 0, offset < fingerprint.byteCount else { throw BusinessAPIClient.Failure.invalidResponse }
            try fileHandle.seek(toOffset: UInt64(offset))
            let amount = Int(min(Int64(chunkSize), fingerprint.byteCount - offset))
            var data = Data()
            while data.count < amount {
                let part = try fileHandle.read(upToCount: amount - data.count) ?? Data()
                guard !part.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                data.append(part)
            }
            status = try await api.sendCaptureChunk(organizationID: org, captureID: item.id, variant: variant,
                                                     offset: offset, bytes: data, token: token)
            guard status.nextOffset > offset, status.nextOffset <= fingerprint.byteCount else { throw BusinessAPIClient.Failure.invalidResponse }
            let fraction = Double(base + status.nextOffset) / Double(total)
            await MainActor.run { CloudUploadProgress.shared.set(item.id, fraction: fraction) }
        }
        if status.state == "verifying" {
            status = try await api.verifyCapture(organizationID: org, captureID: item.id, variant: variant, token: token)
        }
        guard status.state == "verified", try CloudFileFingerprint.read(file) == fingerprint else { throw BusinessAPIClient.Failure.unavailable }
    }
}
