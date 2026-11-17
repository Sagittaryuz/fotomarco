import Foundation

enum ProcessedFileStore {
    static func save(_ data: Data, captureID: UUID = UUID(), root: URL? = nil) throws -> URL {
        guard !data.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let base = try root ?? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Processed", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let url = directory.appendingPathComponent(captureID.uuidString + ".jpg")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
}
