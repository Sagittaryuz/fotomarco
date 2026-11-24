import Foundation

/// Stages immutable copies of indexed historical captures; source files are never moved or deleted.
enum BusinessLegacyLocalImport {
    struct Result: Equatable, Sendable { var staged = 0; var unresolved = 0; var more = false }

    static func stage(root: URL, organizationID: UUID, userID: String, cutoff: Date, limit: Int = 3) throws -> Result {
        guard !userID.isEmpty, limit > 0, limit <= 20 else { throw CocoaError(.fileWriteInvalidFileName) }
        let lookup = PhotoProfileIndex.load(root: root)
        let files = try OriginalStore.files(root: root)
        let journal = BusinessArchiveJournal(root: root)
        let existing = Set(try journal.ids())
        let unfinished = try existing.reduce(0) { $0 + ((try journal.read($1)).finished ? 0 : 1) }
        // Keep the queue bounded so a disconnected cloud account cannot fill the device.
        var originals: [UUID: OriginalFile] = [:]
        for file in files where !file.isVideo && !file.isProcessed {
            if let id = UUID(uuidString: file.url.deletingPathExtension().lastPathComponent), originals[id] == nil { originals[id] = file }
        }
        var result = Result()
        var seen = Set<UUID>()
        let processed = files.filter { !$0.isVideo && $0.isProcessed }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        for file in processed {
            guard let id = UUID(uuidString: file.url.deletingPathExtension().lastPathComponent), seen.insert(id).inserted else { continue }
            guard let date = lookup.dates[id], date <= cutoff, lookup.captures[id]?.id == organizationID else {
                if lookup.dates[id] == nil { result.unresolved += 1 }
                continue
            }
            if existing.contains(id) {
                let current = try journal.read(id)
                guard current.organizationID == organizationID, current.userID == userID, current.createdAt == date else { continue }
                if !current.ready {
                    guard result.staged < limit else { result.more = true; continue }
                    try journal.markReady(id: id, stampedSource: file.url)
                    result.staged += 1
                }
                continue
            }
            guard result.staged < min(limit, max(0, 3 - unfinished)) else { result.more = true; continue }
            let original = originals[id]
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: root.path)
            let free = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let stampedBytes = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            let originalBytes = original.flatMap { try? $0.url.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map { Int64($0) } ?? 0
            guard free > max(1_000_000_000, (stampedBytes + originalBytes) * 2 + 200_000_000) else { result.more = true; continue }
            let ext = original?.url.pathExtension.lowercased() ?? "jpg"
            let target = BusinessCaptureTarget(organizationID: organizationID, userID: userID, keepsOriginal: original != nil)
            try journal.enqueue(id: id, date: date, originalExtension: ext, source: original?.url ?? file.url,
                                target: target, profile: CaptureProfileTag(id: organizationID, name: "JMD Hamoa"))
            try journal.markReady(id: id, stampedSource: file.url)
            result.staged += 1
        }
        return result
    }
}
