import Foundation

/// A resumable cleanup of app-owned copies, after remote verification.
/// It never touches the iOS Photos library or any other app's files.
actor CloudCaptureCleanup {
    enum Result: Equatable { case cleaned, retained }
    typealias Verify = (_ id: String) async -> Bool
    private let queue: CloudCaptureQueue
    private let root: URL
    private let accountIsCurrent: (String) async -> Bool
    private let verify: Verify
    private var inFlight = Set<UUID>()

    init(queue: CloudCaptureQueue, root: URL, accountIsCurrent: @escaping (String) async -> Bool,
         verify: @escaping Verify) {
        self.queue = queue
        self.root = root.standardizedFileURL
        self.accountIsCurrent = accountIsCurrent
        self.verify = verify
    }

    func clean(id: UUID, owner: String, cloudOnlyEnabled: Bool) async -> Result {
        guard cloudOnlyEnabled, root == queue.rootDirectory, !owner.isEmpty, await accountIsCurrent(owner),
              let item = try? queue.entry(id: id), item.ownerHash == CloudCaptureQueue.ownerHash(owner),
              item.phase == .verified || item.phase == .cleaning,
              let originalID = item.originalMediaID, let stampedID = item.processedMediaID,
              let originalHash = item.originalFingerprint, let stampedHash = item.processedFingerprint,
              inFlight.insert(id).inserted else { return .retained }
        defer { inFlight.remove(id) }
        guard await verify(originalID), await accountIsCurrent(owner),
              await verify(stampedID), await accountIsCurrent(owner) else { return .retained }

        let original = root.appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(id.uuidString + "." + item.originalExtension)
        let stamped = root.appendingPathComponent("Processed", isDirectory: true)
            .appendingPathComponent(id.uuidString + ".jpg")
        do {
            if item.phase == .verified { try queue.beginCleanup(id: id, owner: owner) }
            guard await accountIsCurrent(owner) else { return .retained }
            if FileManager.default.fileExists(atPath: original.path) {
                guard try CloudFileFingerprint.read(original) == originalHash else { return .retained }
                try FileManager.default.removeItem(at: original)
            }
            guard await accountIsCurrent(owner) else { return .retained }
            if FileManager.default.fileExists(atPath: stamped.path) {
                guard try CloudFileFingerprint.read(stamped) == stampedHash else { return .retained }
                try FileManager.default.removeItem(at: stamped)
            }
            guard await accountIsCurrent(owner) else { return .retained }
            try queue.finishCleanup(id: id, owner: owner)
            return .cleaned
        } catch { return .retained }
    }
}
