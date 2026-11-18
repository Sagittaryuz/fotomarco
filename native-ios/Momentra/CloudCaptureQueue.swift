import Foundation
import CryptoKit

enum CloudCapturePhase: String, Codable { case awaitingPhoto, ready, uncertain, verified }

struct CloudPendingCapture: Codable, Equatable, Identifiable {
    let id: UUID
    let ownerHash: String
    let originalExtension: String
    let createdAt: Date
    var phase: CloudCapturePhase
    var originalMediaID: String?
    var processedMediaID: String?
    var originalFingerprint: CloudFileFingerprint?
    var processedFingerprint: CloudFileFingerprint?
}

/// A durable journal. Credentials and full-size image bytes are not stored here.
final class CloudCaptureQueue {
    private let directory: URL
    private static let lock = NSLock()

    init(directory: URL) { self.directory = directory }

    static func ownerHash(_ owner: String) -> String {
        SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func enqueue(id: UUID, owner: String, originalExtension: String, at date: Date = Date()) throws {
        guard !owner.isEmpty, owner.utf8.count <= 512 else { throw QueueError.invalid }
        try enqueue(id: id, ownerHash: Self.ownerHash(owner), originalExtension: originalExtension, at: date)
    }

    func enqueue(id: UUID, ownerHash: String, originalExtension: String, at date: Date = Date()) throws {
        guard ownerHash.utf8.count == 64,
              ownerHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              Self.validExtension(originalExtension) else { throw QueueError.invalid }
        Self.lock.lock(); defer { Self.lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard !FileManager.default.fileExists(atPath: path(for: id).path) else { throw QueueError.duplicate }
        try write(CloudPendingCapture(id: id, ownerHash: ownerHash,
            originalExtension: originalExtension.lowercased(), createdAt: date,
            phase: .awaitingPhoto, originalMediaID: nil, processedMediaID: nil,
            originalFingerprint: nil, processedFingerprint: nil))
    }

    func markReady(id: UUID, original: URL, processed: URL) throws {
        try update(id: id) { value in
            guard value.phase == .awaitingPhoto else { throw QueueError.invalidTransition }
            let root = directory.deletingLastPathComponent().standardizedFileURL
            let expectedOriginal = root.appendingPathComponent("Originals", isDirectory: true)
                .appendingPathComponent(id.uuidString + "." + value.originalExtension).standardizedFileURL
            let expectedProcessed = root.appendingPathComponent("Processed", isDirectory: true)
                .appendingPathComponent(id.uuidString + ".jpg").standardizedFileURL
            guard original.standardizedFileURL == expectedOriginal, processed.standardizedFileURL == expectedProcessed else {
                throw QueueError.invalid
            }
            value.originalFingerprint = try CloudFileFingerprint.read(original)
            value.processedFingerprint = try CloudFileFingerprint.read(processed)
            value.phase = .ready
        }
    }

    func markUncertain(id: UUID) throws {
        try update(id: id) { value in
            guard value.phase == .ready else { throw QueueError.invalidTransition }
            value.phase = .uncertain
        }
    }

    func markVerified(id: UUID, originalMediaID: String, processedMediaID: String) throws {
        try update(id: id) { value in
            guard value.phase == .ready, value.originalFingerprint != nil, value.processedFingerprint != nil,
                  GoogleAlbumCoordinator.validID(originalMediaID),
                  GoogleAlbumCoordinator.validID(processedMediaID) else { throw QueueError.invalidTransition }
            value.originalMediaID = originalMediaID
            value.processedMediaID = processedMediaID
            value.phase = .verified
        }
    }

    /// A true result only confirms the local files still match the verified receipt.
    /// The caller must separately revalidate the remote account and album before cleanup.
    func verifiedFilesStillMatch(id: UUID, owner: String, original: URL, processed: URL) throws -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let item = try read(id)
        guard item.phase == .verified, item.ownerHash == Self.ownerHash(owner),
              let expectedOriginal = item.originalFingerprint, let expectedProcessed = item.processedFingerprint,
              item.originalMediaID != nil, item.processedMediaID != nil else { return false }
        let root = directory.deletingLastPathComponent().standardizedFileURL
        let originalPath = root.appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(id.uuidString + "." + item.originalExtension).standardizedFileURL
        let processedPath = root.appendingPathComponent("Processed", isDirectory: true)
            .appendingPathComponent(id.uuidString + ".jpg").standardizedFileURL
        guard original.standardizedFileURL == originalPath, processed.standardizedFileURL == processedPath else { return false }
        guard let currentOriginal = try? CloudFileFingerprint.read(original),
              let currentProcessed = try? CloudFileFingerprint.read(processed) else { return false }
        return currentOriginal == expectedOriginal && currentProcessed == expectedProcessed
    }

    func entries(for owner: String) throws -> [CloudPendingCapture] {
        guard !owner.isEmpty else { throw QueueError.invalid }
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let hash = Self.ownerHash(owner)
        var result: [CloudPendingCapture] = []
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw QueueError.invalid }
            let value = try read(id)
            if value.ownerHash == hash { result.append(value) }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }

    private func update(id: UUID, change: (inout CloudPendingCapture) throws -> Void) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var value = try read(id)
        try change(&value)
        try write(value)
    }

    private func read(_ id: UUID) throws -> CloudPendingCapture {
        let data = try Data(contentsOf: path(for: id))
        guard data.count <= 8192, let value = try? JSONDecoder().decode(CloudPendingCapture.self, from: data),
              value.id == id, Self.validExtension(value.originalExtension) else { throw QueueError.invalid }
        return value
    }

    private func write(_ value: CloudPendingCapture) throws {
        try JSONEncoder().encode(value).write(to: path(for: value.id),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func path(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private static func validExtension(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 12 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }
    enum QueueError: Error { case invalid, duplicate, invalidTransition }
}
