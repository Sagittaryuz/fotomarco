import Foundation
import LockedCameraCapture

/// Session content is invalidated only after all recognized files and metadata have verified durable copies.
@available(iOS 18.0, *)
enum LockedCaptureImporter {
    private actor Imports {
        var active = Set<URL>()
        func begin(_ directory: URL) -> Bool { active.insert(directory).inserted }
        func end(_ directory: URL) { active.remove(directory) }
    }

    private static let imports = Imports()

    static func watch() async {
        for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
            switch update {
            case .initial(let directories):
                for directory in directories { await copySession(directory) }
            case .added(let directory):
                await copySession(directory)
            case .removed:
                break
            @unknown default:
                break
            }
        }
    }

    /// Imports currently available locked sessions once, including when the
    /// containing app is launched by a scheduled background task.
    static func importExisting() async {
        for directory in LockedCameraCaptureManager.shared.sessionContentURLs {
            guard !Task.isCancelled else { return }
            await copySession(directory)
        }
    }

    private static func copySession(_ directory: URL) async {
        guard await imports.begin(directory) else { return }
        let outcome = await Task.detached(priority: .utility) { () -> (staged: Int, safe: Bool, cleanup: [UnselectedOriginal]) in
            let fm = FileManager.default
            guard let root = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return (0, false, []) }
            let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
            let archive = CloudArchiveJournal(root: root)
            copyFiles(from: directory, to: root.appendingPathComponent("Originals", isDirectory: true), cloudQueue: queue, archive: archive)
            copyFiles(from: directory.appendingPathComponent("Processed", isDirectory: true),
                      to: root.appendingPathComponent("Processed", isDirectory: true), cloudQueue: queue, archive: archive)
            let staged = importMetadata(from: directory, to: root, allowedCloudOwnerHash: nil, preserveLegacy: true)
            let safe = sessionIsSafelyImported(directory, root: root, allowedCloudOwnerHash: nil, preserveLegacy: true)
            return (staged, safe, safe ? unselectedOriginals(in: directory, root: root) : [])
        }.value
        if outcome.safe {
            // The system owns these session URLs; never remove a session directory directly.
            do {
                try await LockedCameraCaptureManager.shared.invalidateSessionContent(at: directory)
                if !outcome.cleanup.isEmpty {
                    await Task.detached(priority: .utility) {
                        for item in outcome.cleanup {
                            CloudArchiveJournal(root: item.root).serializeCleanup {
                                guard (try? CloudFileFingerprint.read(item.stamped)) == item.stampedHash,
                                      (try? CloudFileFingerprint.read(item.original)) == item.originalHash else { return }
                                try? FileManager.default.removeItem(at: item.original)
                            }
                        }
                    }.value
                }
            } catch { /* Keep the verified local copies if the system retains the session. */ }
        }
        if outcome.staged > 0 {
            CloudBackgroundScheduler.scheduleIfNeeded()
            NotificationCenter.default.post(name: .momentraCloudCaptureStaged, object: nil)
        }
        await imports.end(directory)
    }

    private struct UnselectedOriginal {
        let root: URL
        let original: URL
        let stamped: URL
        let originalHash: CloudFileFingerprint
        let stampedHash: CloudFileFingerprint
    }

    private static func unselectedOriginals(in directory: URL, root: URL) -> [UnselectedOriginal] {
        let metadata = directory.appendingPathComponent("Metadata")
        let files = (try? FileManager.default.contentsOfDirectory(at: metadata, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { file in
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let bytes = try? Data(contentsOf: file), bytes.count <= 64 * 1024,
                  let capture = try? JSONDecoder().decode(LockedCaptureMetadata.self, from: bytes),
                  capture.isValid(for: id), capture.cloudOwnerHash == nil,
                  capture.archivePlan?.keepsOriginal == false else { return nil }
            let name = id.uuidString + ".jpg"
            let original = directory.appendingPathComponent(name)
            let stamped = directory.appendingPathComponent("Processed").appendingPathComponent(name)
            guard let originalHash = try? CloudFileFingerprint.read(original),
                  let stampedHash = try? CloudFileFingerprint.read(stamped) else { return nil }
            return UnselectedOriginal(root: root, original: root.appendingPathComponent("Originals").appendingPathComponent(name),
                stamped: root.appendingPathComponent("Processed").appendingPathComponent(name),
                originalHash: originalHash, stampedHash: stampedHash)
        }
    }

    /// Conservatively accept only a fully known, complete session whose files
    /// match durable copies. Unknown files and partial imports keep the session.
    static func sessionIsSafelyImported(_ directory: URL, root: URL, allowedCloudOwnerHash: String?,
                                        preserveLegacy: Bool = false) -> Bool {
        let fm = FileManager.default
        guard let top = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
              !top.isEmpty else { return false }
        let processedDir = directory.appendingPathComponent("Processed", isDirectory: true)
        let metadataDir = directory.appendingPathComponent("Metadata", isDirectory: true)
        var originals = Set<UUID>()
        for item in top {
            guard let info = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  info.isSymbolicLink != true else { return false }
            if item.lastPathComponent == "Processed" || item.lastPathComponent == "Metadata" {
                guard info.isDirectory == true else { return false }
            } else {
                guard info.isRegularFile == true, item.pathExtension == "jpg",
                      let id = UUID(uuidString: item.deletingPathExtension().lastPathComponent),
                      item.lastPathComponent == id.uuidString + ".jpg",
                      originals.insert(id).inserted else { return false }
            }
        }
        guard !originals.isEmpty,
              let processed = sessionIDs(in: processedDir, fileExtension: "jpg"),
              let metadataIDs = sessionIDs(in: metadataDir, fileExtension: "json"),
              processed == originals, metadataIDs == originals else { return false }
        let profiles = PhotoProfileIndex.load(root: root)
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending"))
        let archive = CloudArchiveJournal(root: root)
        for id in originals {
            let name = id.uuidString + ".jpg"
            let metaURL = metadataDir.appendingPathComponent(id.uuidString + ".json")
            guard let metaInfo = try? metaURL.resourceValues(forKeys: [.fileSizeKey]),
                  let size = metaInfo.fileSize, size > 0, size <= 64 * 1024,
                  let bytes = try? Data(contentsOf: metaURL), bytes.count == size,
                  let metadata = try? JSONDecoder().decode(LockedCaptureMetadata.self, from: bytes),
                  metadata.isValid(for: id),
                  let originalHash = try? CloudFileFingerprint.read(directory.appendingPathComponent(name)),
                  let stampedHash = try? CloudFileFingerprint.read(processedDir.appendingPathComponent(name)) else { return false }
            let item = try? archive.read(id)
            if let plan = metadata.archivePlan, !plan.deliveries.isEmpty {
                guard let item, item.plan.deliveries.map(\.destination) == plan.deliveries.map(\.destination),
                      item.plan.keepLocal == plan.keepLocal,
                      item.plan.keepsOriginal == plan.keepsOriginal else { return false }
            }
            if let item, item.cleanupStarted {
                guard item.original == originalHash, item.stamped == stampedHash else { return false }
            } else {
                guard (try? CloudFileFingerprint.read(root.appendingPathComponent("Originals").appendingPathComponent(name))) == originalHash,
                      (try? CloudFileFingerprint.read(root.appendingPathComponent("Processed").appendingPathComponent(name))) == stampedHash else { return false }
            }
            if let profileID = metadata.profileID, let name = metadata.profileName, !name.isEmpty,
               profiles.captures[id]?.id != profileID { return false }
            if let ownerHash = metadata.cloudOwnerHash, preserveLegacy || ownerHash == allowedCloudOwnerHash {
                guard let item = try? queue.entry(id: id), item.ownerHash == ownerHash,
                      item.originalFingerprint == originalHash, item.processedFingerprint == stampedHash,
                      item.phase == .ready || item.phase == .verified || item.phase == .cleaning || item.phase == .uncertain else { return false }
            }
        }
        return true
    }

    private static func sessionIDs(in directory: URL, fileExtension expected: String) -> Set<UUID>? {
        guard let dirInfo = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              dirInfo.isDirectory == true, dirInfo.isSymbolicLink != true,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return nil }
        var ids = Set<UUID>()
        for file in files {
            guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true, file.pathExtension == expected,
                  let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  file.lastPathComponent == id.uuidString + "." + expected, ids.insert(id).inserted else { return nil }
        }
        return ids
    }

    /// Metadata is trusted only after the copied original (and, for upload,
    /// processed image) matches the corresponding capture-session file.
    @discardableResult
    static func importMetadata(from directory: URL, to root: URL, allowedCloudOwnerHash: String?,
                               preserveLegacy: Bool = false) -> Int {
        let fm = FileManager.default
        let metadataDir = directory.appendingPathComponent("Metadata", isDirectory: true)
        guard let dirInfo = try? metadataDir.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              dirInfo.isDirectory == true, dirInfo.isSymbolicLink != true,
              let files = try? fm.contentsOfDirectory(at: metadataDir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var staged = 0
        for file in files {
            guard file.pathExtension.lowercased() == "json",
                  let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true,
                  let size = info.fileSize, size > 0, size <= 64 * 1024,
                  let bytes = try? Data(contentsOf: file), bytes.count == size,
                  let metadata = try? JSONDecoder().decode(LockedCaptureMetadata.self, from: bytes),
                  metadata.isValid(for: id) else { continue }
            let name = id.uuidString + ".jpg"
            let sourceOriginal = directory.appendingPathComponent(name)
            let localOriginal = root.appendingPathComponent("Originals").appendingPathComponent(name)
            guard let sourceHash = try? CloudFileFingerprint.read(sourceOriginal),
                  let localHash = try? CloudFileFingerprint.read(localOriginal),
                  sourceHash == localHash else { continue }
            if let profileID = metadata.profileID, let profileName = metadata.profileName, !profileName.isEmpty {
                try? PhotoProfileIndex.register(captureID: id,
                    profile: CaptureProfileTag(id: profileID, name: profileName),
                    captureDate: metadata.capturedAt, root: root)
            }
            let plan = metadata.archivePlan.flatMap { $0.deliveries.isEmpty ? nil : $0 }
            let ownerHash = metadata.cloudOwnerHash.flatMap { preserveLegacy || $0 == allowedCloudOwnerHash ? $0 : nil }
            guard plan != nil || ownerHash != nil else { continue }
            let sourceStamped = directory.appendingPathComponent("Processed").appendingPathComponent(name)
            let localStamped = root.appendingPathComponent("Processed").appendingPathComponent(name)
            guard let sourceStampedHash = try? CloudFileFingerprint.read(sourceStamped),
                  let localStampedHash = try? CloudFileFingerprint.read(localStamped),
                  sourceStampedHash == localStampedHash else { continue }
            do {
                if let plan {
                    let profile = metadata.profileID.flatMap { id in
                        metadata.profileName.map { CaptureProfileTag(id: id, name: $0) }
                    }
                    let journal = CloudArchiveJournal(root: root)
                    try journal.enqueue(id: id, date: metadata.capturedAt,
                                        originalExtension: "jpg", plan: plan, profile: profile)
                    if !plan.keepsOriginal { try journal.markReady(id: id) }
                } else if let ownerHash {
                    try CloudCaptureStager.stage(root: root, captureID: id, ownerHash: ownerHash, originalExtension: "jpg")
                }
                staged += 1
            } catch {
                // Both local files and the capture-session files remain untouched.
            }
        }
        return staged
    }

    static func copyFiles(from directory: URL, to destination: URL, cloudQueue: CloudCaptureQueue? = nil,
                          archive: CloudArchiveJournal? = nil) {
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: destination, withIntermediateDirectories: true)) != nil,
              let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        for source in entries {
            guard source.pathExtension.lowercased() == "jpg", let captureID = UUID(uuidString: source.deletingPathExtension().lastPathComponent),
                  let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= 100 * 1024 * 1024,
                  let data = try? Data(contentsOf: source), data.count == size else { continue }
            let target = destination.appendingPathComponent(source.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            let publish = {
                if let cloudQueue {
                    cloudQueue.publishImportedFileIfAllowed(id: captureID) { writeIfAbsent(data, to: target) }
                } else {
                    writeIfAbsent(data, to: target)
                }
            }
            if let archive { archive.publishImportedFileIfAllowed(id: captureID, publish: publish) }
            else { publish() }
        }
    }

    private static func writeIfAbsent(_ data: Data, to target: URL) {
        let fm = FileManager.default
        let staging = target.deletingLastPathComponent().appendingPathComponent(".momentra-import-" + UUID().uuidString)
        do {
            try data.write(to: staging, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            defer { try? fm.removeItem(at: staging) }
            // A hard link in the same directory publishes complete bytes atomically
            // and fails if a target already exists; the session source is untouched.
            try fm.linkItem(at: staging, to: target)
        } catch {
            try? fm.removeItem(at: staging)
        }
    }
}
