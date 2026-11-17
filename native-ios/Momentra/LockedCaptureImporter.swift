import Foundation
import LockedCameraCapture

/// The source is intentionally retained until a future, verified cleanup flow.
@available(iOS 18.0, *)
enum LockedCaptureImporter {
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

    private static func copySession(_ directory: URL) async {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let root = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return }
            let destination = root.appendingPathComponent("Originals", isDirectory: true)
            copyFiles(from: directory, to: destination)
        }.value
    }

    static func copyFiles(from directory: URL, to destination: URL) {
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: destination, withIntermediateDirectories: true)) != nil,
              let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        for source in entries {
            guard source.pathExtension.lowercased() == "jpg", UUID(uuidString: source.deletingPathExtension().lastPathComponent) != nil,
                  let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= 100 * 1024 * 1024,
                  let data = try? Data(contentsOf: source), data.count == size else { continue }
            let target = destination.appendingPathComponent(source.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            writeIfAbsent(data, to: target)
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
