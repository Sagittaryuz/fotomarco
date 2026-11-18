import Foundation
import CryptoKit

/// Coordinates two independent, durably receipted uploads without deleting local files.
/// Authentication and consent remain the responsibility of the caller.
actor CloudPairUploadCoordinator {
    enum Result: Equatable {
        case verified(original: String, stamped: String)
        case pending
        case unavailable
    }

    typealias Upload = (_ bytes: Data, _ receiptID: UUID, _ owner: String,
                        _ filename: String, _ format: GooglePhotoFormat) async -> PersonalUploadOutcome
    private var inFlight = Set<UUID>()
    private let queue: CloudCaptureQueue
    private let root: URL
    private let upload: Upload
    private let accountIsCurrent: (String) async -> Bool

    init(queue: CloudCaptureQueue, root: URL, accountIsCurrent: @escaping (String) async -> Bool,
         upload: @escaping Upload) {
        self.queue = queue
        self.root = root.standardizedFileURL
        self.accountIsCurrent = accountIsCurrent
        self.upload = upload
    }

    func send(id: UUID, owner: String, personalConsent: Bool, originalFilename: String,
              stampedFilename: String) async -> Result {
        guard personalConsent, root == queue.rootDirectory, !owner.isEmpty, await accountIsCurrent(owner),
              let item = try? queue.entries(for: owner).first(where: { $0.id == id }),
              item.phase == .ready,
              let originalHash = item.originalFingerprint, let stampedHash = item.processedFingerprint,
              let format = GooglePhotoFormat(fileExtension: item.originalExtension) else { return .unavailable }

        guard inFlight.insert(id).inserted else { return .pending }
        defer { inFlight.remove(id) }

        let original = root.appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(id.uuidString + "." + item.originalExtension)
        let stamped = root.appendingPathComponent("Processed", isDirectory: true)
            .appendingPathComponent(id.uuidString + ".jpg")
        guard let first = await sendVariant(original, expected: originalHash, receipt: Self.receiptID(capture: id, variant: "original"),
                                             owner: owner, filename: originalFilename, format: format) else { return .unavailable }
        guard case .verified(let firstID) = first else { return .pending }
        guard let second = await sendVariant(stamped, expected: stampedHash, receipt: Self.receiptID(capture: id, variant: "stamped"),
                                              owner: owner, filename: stampedFilename, format: .jpeg) else { return .unavailable }
        guard case .verified(let secondID) = second else { return .pending }

        // Verify local originals did not change while the network operation was running.
        guard await accountIsCurrent(owner),
              (try? CloudFileFingerprint.read(original)) == originalHash,
              (try? CloudFileFingerprint.read(stamped)) == stampedHash else { return .unavailable }
        do {
            try queue.markVerified(id: id, originalMediaID: firstID, processedMediaID: secondID)
            return .verified(original: firstID, stamped: secondID)
        } catch { return .unavailable }
    }

    /// Scope each full-resolution buffer to one transfer instead of retaining both.
    private func sendVariant(_ url: URL, expected: CloudFileFingerprint, receipt: UUID, owner: String,
                             filename: String, format: GooglePhotoFormat) async -> PersonalUploadOutcome? {
        guard await accountIsCurrent(owner), let bytes = try? safeBytes(url, expected: expected),
              await accountIsCurrent(owner) else { return nil }
        return await upload(bytes, receipt, owner, filename, format)
    }

    private func safeBytes(_ url: URL, expected: CloudFileFingerprint) throws -> Data {
        guard try CloudFileFingerprint.read(url) == expected else { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: url)
        guard Int64(data.count) == expected.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected.sha256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    /// Separate, deterministic receipt IDs ensure retrying one variant cannot overwrite the other.
    private static func receiptID(capture: UUID, variant: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(("momentra-v1:" + capture.uuidString + ":" + variant).utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }
}
