import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A small offline preview; full-resolution originals remain separate until remote verification.
enum CloudThumbnailCache {
    enum Failure: Error { case missingSource, invalidImage, encoding }

    private static let visibilityLock = NSLock()
    private static let hiddenKey = "native.camera.deletedThumbnailIDs.v1"

    static func hiddenCaptureIDs(defaults: UserDefaults = .standard) -> Set<String> {
        visibilityLock.lock(); defer { visibilityLock.unlock() }
        return Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    static func setHidden(_ hidden: Bool, captureID: UUID, defaults: UserDefaults = .standard) {
        visibilityLock.lock(); defer { visibilityLock.unlock() }
        var ids = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
        if hidden { ids.insert(captureID.uuidString) } else { ids.remove(captureID.uuidString) }
        defaults.set(Array(ids), forKey: hiddenKey)
    }

    static func latestCapturePreview(root: URL) -> (image: CGImage, file: URL)? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        var hidden = hiddenCaptureIDs()
        // Photos deleted by earlier versions are still identifiable in the local trash.
        let trash = root.appendingPathComponent("CaptureTrash/Processed", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: trash, includingPropertiesForKeys: nil) {
            for case let file as URL in enumerator {
                if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) { hidden.insert(id.uuidString) }
            }
        }
        let candidates = ["Processed", "CloudThumbnails"].flatMap { name in
            let directory = root.appendingPathComponent(name, isDirectory: true)
            return (try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        }.compactMap { url -> (URL, Date)? in
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), hidden.contains(id.uuidString) { return nil }
            guard let attributes = try? url.resourceValues(forKeys: keys), attributes.isRegularFile == true,
                  let date = attributes.contentModificationDate else { return nil }
            return (url, date)
        }.sorted { $0.1 > $1.1 }
        for (url, _) in candidates {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { continue }
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 160
            ] as CFDictionary) { return (thumbnail, url) }
        }
        return nil
    }

    private static let shareLock = NSLock()

    static func shareOriginal(root: URL, captureID: UUID) -> URL? {
        shareLock.lock(); defer { shareLock.unlock() }
        let file = root.appendingPathComponent("QuickShareCache", isDirectory: true).appendingPathComponent(captureID.uuidString + ".jpg")
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size > 0 else { return nil }
        return file
    }

    static func cacheShareOriginal(root: URL, captureID: UUID, source: URL) throws {
        shareLock.lock(); defer { shareLock.unlock() }
        let fm = FileManager.default
        let attrs = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
        guard attrs.isRegularFile == true, let size = attrs.fileSize, size > 0, size <= 64_000_000 else { return }
        let date = attrs.contentModificationDate ?? Date()
        let directory = root.appendingPathComponent("QuickShareCache", isDirectory: true
        )
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var cacheDirectory = directory; try? cacheDirectory.setResourceValues(values)
        let existing = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let output = directory.appendingPathComponent(captureID.uuidString + ".jpg")
        if fm.fileExists(atPath: output.path) { return }
        if existing.contains(where: { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > date }) { return }
        let temporary = directory.appendingPathComponent("." + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)
        try fm.setAttributes([.modificationDate: date, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        try fm.moveItem(at: temporary, to: output)
        for old in existing where old.pathExtension.lowercased() == "jpg" && UUID(uuidString: old.deletingPathExtension().lastPathComponent) != nil { try? fm.removeItem(at: old) }
    }

    static func ensure(root: URL, captureID: UUID, source: URL) throws {
        let directory = root.appendingPathComponent("CloudThumbnails", isDirectory: true)
        let output = directory.appendingPathComponent(captureID.uuidString + ".jpg")
        if let attrs = try? output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
           attrs.isRegularFile == true, attrs.isSymbolicLink != true,
           let size = attrs.fileSize, size > 0, size <= 2_000_000,
           CGImageSourceCreateWithURL(output as CFURL, nil) != nil { return }

        guard FileManager.default.fileExists(atPath: source.path) else { throw Failure.missingSource }
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
              ] as CFDictionary) else { throw Failure.invalidImage }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.encoding
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination), bytes.length > 0, bytes.length <= 2_000_000 else {
            throw Failure.encoding
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try (bytes as Data).write(to: output, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let date = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: output.path)
        }
    }
}
