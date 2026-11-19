import Foundation

/// Separate from CloudPending, which belongs exclusively to Google Photos.
struct CloudArchiveJournal {
    private static let fileLock = NSLock()
    struct Capture: Codable, Identifiable {
        let id: UUID
        let createdAt: Date
        let originalExtension: String
        var plan: CloudDeliveryPlan
        var original: CloudFileFingerprint?
        var stamped: CloudFileFingerprint?
        var reservations: [Reservation] = []
        var cleanupStarted = false
        var finished = false
        var remoteOriginalName: String?
        var remoteStampedName: String?

        struct Reservation: Codable {
            let destination: CloudDeliveryPlan.Destination
            let folder: String
            let original: String?
            let stamped: String
        }

        func remoteName(stamped: Bool) -> String {
            if stamped { return remoteStampedName ?? id.uuidString + "-stamped.jpg" }
            return remoteOriginalName ?? id.uuidString + "-original." + originalExtension
        }
    }

    let root: URL
    private var directory: URL { root.appendingPathComponent("CloudArchivePending", isDirectory: true) }

    static func documents() throws -> Self {
        Self(root: try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true))
    }

    func enqueue(id: UUID, date: Date, originalExtension: String, plan: CloudDeliveryPlan,
                 profile: CaptureProfileTag? = nil) throws {
        guard plan.isValidNewPlan, !plan.deliveries.isEmpty, Self.validExtension(originalExtension),
              (0...253_402_300_799).contains(date.timeIntervalSince1970) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }
        if FileManager.default.fileExists(atPath: path(id).path) {
            let existing = try read(id)
            guard existing.originalExtension == originalExtension, existing.createdAt == date,
                  existing.plan.keepLocal == plan.keepLocal,
                  existing.plan.keepsOriginal == plan.keepsOriginal,
                  existing.plan.deliveries.map(\.destination) == plan.deliveries.map(\.destination) else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }
        var capture = Capture(id: id, createdAt: date, originalExtension: originalExtension, plan: plan)
        capture.remoteOriginalName = CloudArchiveFilename.make(captureID: id, capturedAt: date, profile: profile,
                                                               originalExtension: originalExtension)
        capture.remoteStampedName = CloudArchiveFilename.make(captureID: id, capturedAt: date, profile: profile,
                                                              originalExtension: nil)
        try write(capture)
    }

    func publishImportedFileIfAllowed(id: UUID, publish: () -> Void) {
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }
        if FileManager.default.fileExists(atPath: path(id).path) {
            guard let item = try? read(id), !item.cleanupStarted else { return }
        }
        publish()
    }

    func serializeCleanup(_ action: () throws -> Void) rethrows {
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }
        try action()
    }

    func hasPendingDelivery(id: UUID) -> Bool {
        guard FileManager.default.fileExists(atPath: path(id).path) else { return false }
        return (try? read(id).finished) != true
    }

    func markReady(id: UUID) throws {
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }
        var item = try read(id)
        guard item.original == nil, item.stamped == nil else { return }
        item.original = try CloudFileFingerprint.read(file(item, stamped: false))
        item.stamped = try CloudFileFingerprint.read(file(item, stamped: true))
        try write(item)
    }

    func ids() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }

    func read(_ id: UUID) throws -> Capture {
        let item = try JSONDecoder().decode(Capture.self, from: Data(contentsOf: path(id)))
        let destinations = item.plan.deliveries.map(\.destination)
        guard id == item.id, Self.validExtension(item.originalExtension), !destinations.isEmpty,
              let originalName = CloudArchiveFilename(item.remoteName(stamped: false)),
              originalName.captureID == id, originalName.isOriginal,
              item.remoteName(stamped: false).hasSuffix("." + item.originalExtension),
              let stampedName = CloudArchiveFilename(item.remoteName(stamped: true)),
              stampedName.captureID == id, !stampedName.isOriginal,
              originalName.capturedAt == stampedName.capturedAt,
              Set(destinations).count == destinations.count,
              destinations.allSatisfy({
                  CloudDeliveryPlan.Destination(provider: $0.provider, accountHash: $0.accountHash) != nil
              }), (item.original == nil) == (item.stamped == nil),
              !item.cleanupStarted || (!item.plan.keepLocal && item.plan.destinationsVerified),
              !item.finished || item.plan.destinationsVerified else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return item
    }

    func write(_ item: Capture) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(item).write(to: path(item.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func file(_ item: Capture, stamped: Bool) -> URL {
        root.appendingPathComponent(stamped ? "Processed" : "Originals", isDirectory: true)
            .appendingPathComponent(item.id.uuidString + "." + (stamped ? "jpg" : item.originalExtension))
    }

    private func path(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    private static func validExtension(_ value: String) -> Bool {
        (1...12).contains(value.utf8.count) &&
            value.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) }
    }
}
