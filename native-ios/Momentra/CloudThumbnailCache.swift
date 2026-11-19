import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A small offline preview; full-resolution originals remain separate until remote verification.
enum CloudThumbnailCache {
    enum Failure: Error { case missingSource, invalidImage, encoding }

    static func latestCapturePreview(root: URL) -> (image: CGImage, file: URL)? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let candidates = ["Processed", "CloudThumbnails"].flatMap { name in
            let directory = root.appendingPathComponent(name, isDirectory: true)
            return (try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        }.compactMap { url -> (URL, Date)? in
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
