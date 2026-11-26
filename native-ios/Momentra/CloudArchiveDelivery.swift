import Foundation
import UniformTypeIdentifiers

actor CloudArchiveDelivery {
    static let shared = CloudArchiveDelivery()
    struct Summary {
        var pending = 0
        var needsAttention = false
        var issues: [String] = []
    }

    private var running = false
    private let google = GoogleDriveArchive()
    private let microsoft = OneDriveArchive()

    func drain() async -> Summary? {
        guard !running else { return nil }
        running = true
        defer { running = false }
        var summary = Summary()
        var changedDestinations = Set<CloudDeliveryPlan.Destination>()
        do {
            let journal = try CloudArchiveJournal.documents()
            let ids = try journal.ids()
            let pending = Set(ids.filter { (try? journal.read($0).finished) != true })
            await MainActor.run { CloudUploadProgress.shared.preparePending(pending) }
            for id in ids {
                do {
                    var item = try journal.read(id)
                    guard !item.finished else { continue }
                    try Task.checkCancellation()
                    if item.original == nil {
                        try journal.markReady(id: id)
                        item = try journal.read(id)
                    }
                    await MainActor.run { CloudUploadProgress.shared.start(id) }
                    try await send(&item, journal: journal, changedDestinations: &changedDestinations)
                    await MainActor.run { CloudUploadProgress.shared.finish(id) }
                } catch {
                    await MainActor.run { CloudUploadProgress.shared.stop(id) }
                    summary.pending += 1
                    if (error as? URLError)?.code != .notConnectedToInternet {
                        summary.needsAttention = true
                        if let problem = error as? DeliveryProblems {
                            for issue in problem.messages where !summary.issues.contains(issue) {
                                summary.issues.append(issue)
                            }
                        }
                    }
                }
            }
        } catch { summary.needsAttention = true }
        if !changedDestinations.isEmpty {
            for destination in changedDestinations { await CloudGalleryCatalog.shared.invalidate(destination) }
            await MainActor.run { NotificationCenter.default.post(name: CloudGalleryCatalog.deliveryChanged, object: nil) }
        }
        return summary
    }

    private func send(_ item: inout CloudArchiveJournal.Capture, journal: CloudArchiveJournal,
                      changedDestinations: inout Set<CloudDeliveryPlan.Destination>) async throws {
        guard let original = item.original, let stamped = item.stamped else { throw CocoaError(.fileReadCorruptFile) }
        let originalURL = journal.file(item, stamped: false)
        let stampedURL = journal.file(item, stamped: true)

        if !item.cleanupStarted {
            if item.plan.keepsOriginal, try CloudFileFingerprint.read(originalURL) != original {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard try CloudFileFingerprint.read(stampedURL) == stamped else { throw CocoaError(.fileReadCorruptFile) }
        }

        var failures: [Error] = []
        let originalBytes = item.plan.keepsOriginal ? Double(original.byteCount) : 0
        let stampedBytes = Double(stamped.byteCount)
        let bytesPerDestination = originalBytes + stampedBytes
        let totalBytes = max(1, bytesPerDestination * Double(item.plan.deliveries.count))
        let captureID = item.id
        var completedBytes = 0.0
        var organizationStorageIdentity: String?
        for delivery in item.plan.deliveries {
            let base = completedBytes
            let originalProgress: @Sendable (Double) -> Void = { value in
                let fraction = (base + value * originalBytes) / totalBytes
                Task { @MainActor in CloudUploadProgress.shared.set(captureID, fraction: fraction) }
            }
            let stampedProgress: @Sendable (Double) -> Void = { value in
                let fraction = (base + originalBytes + value * stampedBytes) / totalBytes
                Task { @MainActor in CloudUploadProgress.shared.set(captureID, fraction: fraction) }
            }
            let destination = delivery.destination
            let originalName = item.remoteName(stamped: false, destination: destination)
            let stampedName = item.remoteName(stamped: true, destination: destination)
            do {
                try Task.checkCancellation()
                if delivery.phase == .duplicate {
                    guard item.plan.keepLocal, item.plan.organizationDedup?.isValid == true,
                          delivery.originalID == nil, delivery.stampedID == nil else { throw CocoaError(.fileReadCorruptFile) }
                    completedBytes += bytesPerDestination
                    continue
                }
                if delivery.phase == .verified, item.plan.keepLocal {
                    completedBytes += bytesPerDestination
                    continue
                }
                if let context = item.plan.organizationDedup, delivery.phase == .pending {
                    if organizationStorageIdentity == nil {
                        organizationStorageIdentity = try await Self.businessStorageIdentity(for: context)
                    }
                    let decision = try await CloudStorageIdentity.decide(organization: { organizationStorageIdentity }, personal: {
                        try await CloudArchiveAccounts.shared.storageFingerprint(for: destination, userID: context.userID)
                    })
                    let stillSignedIn = await MainActor.run { BusinessIdentity.shared.userID == context.userID && BusinessIdentity.shared.emailVerified }
                    guard stillSignedIn else { throw CocoaError(.userCancelled) }
                    switch decision {
                    case .same:
                        item.plan.markDuplicate(destination: destination)
                        try journal.write(item)
                        completedBytes += bytesPerDestination
                        continue
                    case .different: break
                    case .unknown: throw CocoaError(.fileReadUnknown)
                    }
                }
                let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
                switch destination.provider {
                case .googleDrive:
                    let mime = UTType(filenameExtension: item.originalExtension)?.preferredMIMEType ?? "application/octet-stream"
                    let reservation: CloudArchiveJournal.Capture.Reservation
                    if let existing = item.reservations.first(where: { $0.destination == destination }) {
                        reservation = existing
                    } else {
                        guard delivery.phase != .verified else { throw CocoaError(.fileReadCorruptFile) }
                        let folder = try await google.folder(accessToken: token)
                        let first = item.plan.keepsOriginal ? try await google.reserveFileID(accessToken: token) : nil
                        let second = try await google.reserveFileID(accessToken: token)
                        guard first != second else { throw CocoaError(.fileReadCorruptFile) }
                        reservation = .init(destination: destination, folder: folder, original: first, stamped: second)
                        item.reservations.append(reservation)
                        try journal.write(item)
                    }
                    guard item.plan.keepsOriginal == (reservation.original != nil) else { throw CocoaError(.fileReadCorruptFile) }
                    if delivery.phase == .verified {
                        guard delivery.originalID == reservation.original, delivery.stampedID == reservation.stamped else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        if let first = reservation.original {
                            try await google.verify(id: first, folderID: reservation.folder, name: originalName, mimeType: mime, fingerprint: original, accessToken: token)
                        }
                        try await google.verify(id: reservation.stamped, folderID: reservation.folder, name: stampedName, mimeType: "image/jpeg", fingerprint: stamped, accessToken: token)
                    } else {
                        let first: String?
                        if let id = reservation.original {
                            first = try await google.upload(file: originalURL, id: id, folderID: reservation.folder, name: originalName, mimeType: mime, fingerprint: original, accessToken: token, progress: originalProgress)
                        } else { first = nil }
                        let second = try await google.upload(file: stampedURL, id: reservation.stamped, folderID: reservation.folder, name: stampedName, mimeType: "image/jpeg", fingerprint: stamped, accessToken: token, progress: stampedProgress)
                        try confirm(&item, destination: destination, original: first, stamped: second, journal: journal)
                        changedDestinations.insert(destination)
                    }
                case .oneDrive:
                    if delivery.phase == .verified {
                        guard let second = delivery.stampedID, delivery.originalID != second,
                              item.plan.keepsOriginal == (delivery.originalID != nil) else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        if let first = delivery.originalID {
                            try await microsoft.verify(id: first, name: originalName, fingerprint: original, accessToken: token)
                        }
                        try await microsoft.verify(id: second, name: stampedName, fingerprint: stamped, accessToken: token)
                    } else {
                        let first = item.plan.keepsOriginal
                            ? try await microsoft.upload(originalURL, name: originalName, fingerprint: original, accessToken: token, progress: originalProgress) : nil
                        let second = try await microsoft.upload(stampedURL, name: stampedName, fingerprint: stamped, accessToken: token, progress: stampedProgress)
                        try confirm(&item, destination: destination, original: first, stamped: second, journal: journal)
                        changedDestinations.insert(destination)
                    }
                }
                completedBytes += bytesPerDestination
            } catch { failures.append(error) }
        }
        if !failures.isEmpty {
            if failures.allSatisfy({ ($0 as? URLError)?.code == .notConnectedToInternet }) {
                throw URLError(.notConnectedToInternet)
            }
            throw DeliveryProblems(messages: failures.compactMap { error in
                if let error = error as? GoogleDriveArchive.ArchiveError { return error.errorDescription }
                if let error = error as? OneDriveArchive.Failure { return error.errorDescription }
                if let error = error as? CloudArchiveOAuth.Failure { return error.errorDescription }
                return nil
            })
        }
        guard item.plan.destinationsVerified else { throw CocoaError(.fileReadCorruptFile) }
        if !item.plan.keepLocal {
            try Task.checkCancellation()
            try journal.serializeCleanup {
                try clean(&item, journal: journal, original: original, stamped: stamped)
            }
        }
        item.finished = true
        try journal.write(item)
    }

    private struct DeliveryProblems: Error {
        let messages: [String]
    }

    private static func businessStorageIdentity(for context: CloudDeliveryPlan.OrganizationDedup) async throws -> String {
        guard context.isValid, let api = BusinessAPIClient.configured() else { throw CocoaError(.fileReadUnknown) }
        let token = try await BusinessIdentity.shared.verifiedToken(expectedUserID: context.userID)
        let organizations = try await api.myOrganizations(token: token).organizations
        let stillSignedIn = await MainActor.run { BusinessIdentity.shared.userID == context.userID && BusinessIdentity.shared.emailVerified }
        guard stillSignedIn, let organization = organizations.first(where: { UUID(uuidString: $0.id) == context.organizationID && $0.captureReady == true }),
              let identity = organization.storageIdentity, CloudStorageIdentity.compare(identity, identity) == .same else {
            throw CocoaError(.fileReadUnknown)
        }
        return identity
    }

    private func confirm(_ item: inout CloudArchiveJournal.Capture, destination: CloudDeliveryPlan.Destination,
                         original: String?, stamped: String, journal: CloudArchiveJournal) throws {
        guard item.plan.keepsOriginal == (original != nil), original?.isEmpty != true,
              !stamped.isEmpty, original != stamped else { throw CocoaError(.fileReadCorruptFile) }
        item.plan.confirm(destination: destination, originalID: original, stampedID: stamped)
        try journal.write(item)
    }

    private func clean(_ item: inout CloudArchiveJournal.Capture, journal: CloudArchiveJournal,
                       original: CloudFileFingerprint, stamped: CloudFileFingerprint) throws {
        let originalFile = journal.file(item, stamped: false)
        let stampedFile = journal.file(item, stamped: true)
        let files = [(originalFile, original), (stampedFile, stamped)]
        for (file, fingerprint) in files {
            if (item.cleanupStarted || (!item.plan.keepsOriginal && file == originalFile)),
               !FileManager.default.fileExists(atPath: file.path) { continue }
            guard try CloudFileFingerprint.read(file) == fingerprint else { throw CocoaError(.fileReadCorruptFile) }
        }
        if !item.cleanupStarted {
            try CloudThumbnailCache.ensure(root: journal.root, captureID: item.id, source: stampedFile)
            try? CloudThumbnailCache.cacheShareOriginal(root: journal.root, captureID: item.id, source: stampedFile)
            item.cleanupStarted = true
            try journal.write(item)
        }
        for (file, _) in files where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
