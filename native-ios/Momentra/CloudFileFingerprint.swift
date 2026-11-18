import Foundation
import CryptoKit

struct CloudFileFingerprint: Codable, Equatable {
    let byteCount: Int64
    let sha256: String

    /// Hash the file incrementally; do not load full-resolution images into memory.
    static func read(_ url: URL) throws -> CloudFileFingerprint {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              let length = properties.fileSize, length > 0, length <= 200 * 1024 * 1024 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        var read: Int64 = 0
        while true {
            let block = try file.read(upToCount: 1_048_576) ?? Data()
            if block.isEmpty { break }
            hasher.update(data: block)
            read += Int64(block.count)
            guard read <= Int64(length) else { throw CocoaError(.fileReadCorruptFile) }
        }
        let after = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard read == Int64(length), after.isRegularFile == true, after.isSymbolicLink != true,
              after.fileSize == length, after.contentModificationDate == properties.contentModificationDate else { throw CocoaError(.fileReadCorruptFile) }
        return CloudFileFingerprint(byteCount: read, sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
