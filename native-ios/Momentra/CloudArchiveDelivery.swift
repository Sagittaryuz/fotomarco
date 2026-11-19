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
        do {
            let journal = try CloudArchiveJournal.documents()
            for id in try journal.ids() {
                do {
                    var item = try journal.read(id)
                    guard !item.finished else { continue }
                    try Task.checkCancellation()
                    if item.original == nil {
                        try journal.markReady(id: id)
                        item = try journal.read(id)
                    }
                    try await send(&item, journal: journal)
                } catch {
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
        return summary
    }

    private func send(_ item: inout CloudArchiveJournal.Capture, journal: CloudArchiveJournal) async throws {
        guard let original = item.original, let stamped = item.stamped else { throw CocoaError(.fileReadCorruptFile) }
        let originalURL = journal.file(item, stamped: false)
        let stampedURL = journal.file(item, stamped: true)
        let originalName = item.remoteName(stamped: false)
        let stampedName = item.remoteName(stamped: true)

        if !item.cleanupStarted {
            if item.plan.keepsOriginal, try CloudFileFingerprint.read(originalURL) != original {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard try CloudFileFingerprint.read(stampedURL) == stamped else { throw CocoaError(.fileReadCorruptFile) }
        }

        var failures: [Error] = []
        for delivery in item.plan.deliveries {
            let destination = delivery.destination
            do {
                try Task.checkCancellation()
                if delivery.phase == .verified, item.plan.keepLocal { continue }
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
                            first = try await google.upload(file: originalURL, id: id, folderID: reservation.folder, name: originalName, mimeType: mime, fingerprint: original, accessToken: token)
                        } else { first = nil }
                        let second = try await google.upload(file: stampedURL, id: reservation.stamped, folderID: reservation.folder, name: stampedName, mimeType: "image/jpeg", fingerprint: stamped, accessToken: token)
                        try confirm(&item, destination: destination, original: first, stamped: second, journal: journal)
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
                            ? try await microsoft.upload(originalURL, name: originalName, fingerprint: original, accessToken: token) : nil
                        let second = try await microsoft.upload(stampedURL, name: stampedName, fingerprint: stamped, accessToken: token)
                        try confirm(&item, destination: destination, original: first, stamped: second, journal: journal)
                    }
                }
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
            item.cleanupStarted = true
            try journal.write(item)
        }
        for (file, _) in files where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
