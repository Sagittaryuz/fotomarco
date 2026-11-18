import Foundation

/// Small non-secret context stored with a locked capture until the app imports it.
struct LockedCaptureMetadata: Codable {
    static let cloudTaskIdentifier = "br.com.momentra.camera.cloud-processing"
    let captureID: UUID
    let capturedAt: Date
    let profileID: UUID?
    let profileName: String?
    let cloudOwnerHash: String?

    static func safeProfileName(_ name: String) -> String {
        let result = bounded(name, characters: 60, bytes: 240)
        return result.isEmpty ? "Perfil" : result
    }
    static func safeNote(_ note: String) -> String { bounded(note, characters: 96, bytes: 384) }

    private static func bounded(_ text: String, characters: Int, bytes: Int) -> String {
        var result = String(text.prefix(characters))
        while result.utf8.count > bytes { result.removeLast() }
        return result
    }

    func isValid(for id: UUID) -> Bool {
        guard captureID == id, capturedAt.timeIntervalSince1970.isFinite,
              profileName.map({ !$0.isEmpty && $0.utf8.count <= 240 }) ?? true,
              (profileID == nil) == (profileName == nil) else { return false }
        if let hash = cloudOwnerHash {
            guard hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return false }
        }
        return true
    }
}
