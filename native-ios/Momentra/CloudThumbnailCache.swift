import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A small offline preview; full-resolution originals remain separate until remote verification.
enum CloudThumbnailCache {
    enum Failure: Error { case missingSource, invalidImage, encoding }

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
    }
}
