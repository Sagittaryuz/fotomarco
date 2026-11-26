import Foundation

struct BusinessCaptureTarget: Equatable, Sendable {
    let organizationID: UUID
    let userID: String
    let keepsOriginal: Bool
}

/// Separate durable copies prevent personal-gallery cleanup from deleting unsent team photos.
struct BusinessArchiveJournal {
    struct Capture: Codable, Identifiable {
        let id: UUID
        let organizationID: UUID
        let userID: String
        let createdAt: Date
        let originalExtension: String
        let originalName: String
        let stampedName: String
        let keepsOriginal: Bool
        let original: CloudFileFingerprint?
        var stamped: CloudFileFingerprint?
        var originalVerified = false
        var stampedVerified = false
        var ready: Bool { stamped != nil }
        var finished: Bool { stampedVerified && (!keepsOriginal || originalVerified) }
    }

    private static let lock = NSRecursiveLock()
    let root: URL
    private var directory: URL { root.appendingPathComponent("BusinessArchivePending", isDirectory: true) }

    static func documents() throws -> Self {
        Self(root: try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true))
    }

    func enqueue(id: UUID, date: Date, originalExtension: String, source: URL,
                 target: BusinessCaptureTarget, profile: CaptureProfileTag) throws {
        guard profile.id == target.organizationID, !target.userID.isEmpty, target.userID.utf8.count <= 128,
              target.userID.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
              originalExtension.range(of: #"^[a-z0-9]{1,12}$"#, options: .regularExpression) != nil else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        Self.lock.lock(); defer { Self.lock.unlock() }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        if fileManager.fileExists(atPath: metadataURL(id).path) {
            let existing = try read(id)
            guard existing.organizationID == target.organizationID, existing.userID == target.userID,
                  existing.createdAt == date, existing.originalExtension == originalExtension,
                  existing.keepsOriginal == target.keepsOriginal else { throw CocoaError(.fileWriteFileExists) }
            return
        }
        guard let originalName = CloudArchiveFilename.renamed(CloudArchiveFilename.make(captureID: id, capturedAt: date,
                    profile: profile, originalExtension: originalExtension), provider: .oneDrive, timeZone: .current),
              let stampedName = CloudArchiveFilename.renamed(CloudArchiveFilename.make(captureID: id, capturedAt: date,
                    profile: profile, originalExtension: nil), provider: .oneDrive, timeZone: .current) else { throw CocoaError(.fileWriteInvalidFileName) }
        var fingerprint: CloudFileFingerprint?
        if target.keepsOriginal {
            let sourceHash = try CloudFileFingerprint.read(source)
            let destination = originalURL(id, ext: originalExtension)
            if !fileManager.fileExists(atPath: destination.path) { try fileManager.copyItem(at: source, to: destination) }
            let copiedHash = try CloudFileFingerprint.read(destination)
            guard copiedHash == sourceHash else { throw CocoaError(.fileReadCorruptFile) }
            fingerprint = copiedHash
        }
        let capture = Capture(id: id, organizationID: target.organizationID, userID: target.userID, createdAt: date,
            originalExtension: originalExtension, originalName: originalName, stampedName: stampedName,
            keepsOriginal: target.keepsOriginal, original: fingerprint)
        try write(capture)
    }

    func markReady(id: UUID, stampedSource: URL) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var capture = try read(id)
        if capture.stamped != nil { return }
        let sourceHash = try CloudFileFingerprint.read(stampedSource)
        let destination = stampedURL(id)
        if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: stampedSource, to: destination) }
        let copiedHash = try CloudFileFingerprint.read(destination)
        guard copiedHash == sourceHash else { throw CocoaError(.fileReadCorruptFile) }
        capture.stamped = copiedHash
        try write(capture)
    }

    func ids() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }

    func read(_ id: UUID) throws -> Capture {
        let data = try Data(contentsOf: metadataURL(id))
        let capture = try JSONDecoder().decode(Capture.self, from: data)
        guard capture.id == id else { throw CocoaError(.fileReadCorruptFile) }
        return capture
    }

    /// A duplicate personal upload may be skipped only after the matching team
    /// copy has a verified receipt for the exact files and organization.
    func confirmsDelivery(id: UUID, organizationID: UUID, userID: String,
                          stamped: CloudFileFingerprint, original: CloudFileFingerprint?, keepsOriginal: Bool) -> Bool {
        guard let item = try? read(id), item.organizationID == organizationID, item.userID == userID,
              item.finished, item.stamped == stamped, item.keepsOriginal == keepsOriginal else { return false }
        return keepsOriginal ? item.original == original && original != nil : item.original == nil
    }

    func markVerified(_ id: UUID, variant: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var capture = try read(id)
        if variant == "original", capture.keepsOriginal, capture.original != nil { capture.originalVerified = true }
        else if variant == "stamped", capture.stamped != nil { capture.stampedVerified = true }
        else { throw CocoaError(.fileReadCorruptFile) }
        try write(capture)
    }

    func originalURL(_ capture: Capture) -> URL { originalURL(capture.id, ext: capture.originalExtension) }
    func stampedURL(_ capture: Capture) -> URL { stampedURL(capture.id) }
    private func originalURL(_ id: UUID, ext: String) -> URL { directory.appendingPathComponent(id.uuidString + "-original." + ext) }
    private func stampedURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + "-stamped.jpg") }
    private func metadataURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func write(_ capture: Capture) throws {
        let data = try JSONEncoder().encode(capture)
        try data.write(to: metadataURL(capture.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
