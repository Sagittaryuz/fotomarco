import Foundation

/// Registers already-preserved files for later delivery. Does not delete, upload,
/// or alter either photo. Repeated staging is safe only for the same account/files.
enum CloudCaptureStager {
    enum StageError: Error { case conflictingCapture }

    static func stage(root: URL, captureID: UUID, ownerHash: String, originalExtension: String) throws {
        let queue = CloudCaptureQueue(directory: root.appendingPathComponent("CloudPending", isDirectory: true))
        let original = root.appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(captureID.uuidString + "." + originalExtension.lowercased())
        let stamped = root.appendingPathComponent("Processed", isDirectory: true)
            .appendingPathComponent(captureID.uuidString + ".jpg")
        do {
            try queue.enqueue(id: captureID, ownerHash: ownerHash, originalExtension: originalExtension)
        } catch CloudCaptureQueue.QueueError.duplicate {
            let existing = try queue.entry(id: captureID)
            guard existing.ownerHash == ownerHash, existing.originalExtension == originalExtension.lowercased() else {
                throw StageError.conflictingCapture
            }
            if existing.phase == .ready {
                guard try CloudFileFingerprint.read(original) == existing.originalFingerprint,
                      try CloudFileFingerprint.read(stamped) == existing.processedFingerprint else {
                    throw StageError.conflictingCapture
                }
                return
            }
            guard existing.phase == .awaitingPhoto else { throw StageError.conflictingCapture }
        }
        try queue.markReady(id: captureID, original: original, processed: stamped)
    }
}
