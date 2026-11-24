import Foundation

/// Copies a discovered cloud capture into the durable upload queue. Sources remain untouched.
enum BusinessLegacyCloudStage {
    static func stage(root: URL, stamped: URL, original: URL?, captureID: UUID, date: Date,
                      organizationID: UUID, userID: String, cutoff: Date) throws {
        guard date <= cutoff else { throw CocoaError(.fileWriteInvalidFileName) }
        let lookup = PhotoProfileIndex.load(root: root)
        if let existing = lookup.captures[captureID], existing.id != organizationID { throw CocoaError(.fileWriteFileExists) }
        let profile = CaptureProfileTag(id: organizationID, name: "JMD Hamoa")
        try PhotoProfileIndex.register(captureID: captureID, profile: profile, captureDate: date, root: root)
        let ext = original?.pathExtension.lowercased() ?? "jpg"
        let journal = BusinessArchiveJournal(root: root)
        try journal.enqueue(id: captureID, date: date, originalExtension: ext, source: original ?? stamped,
            target: .init(organizationID: organizationID, userID: userID, keepsOriginal: original != nil), profile: profile)
        try journal.markReady(id: captureID, stampedSource: stamped)
    }
}
