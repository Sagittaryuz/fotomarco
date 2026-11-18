import Foundation
import CryptoKit

struct GoogleAlbum: Decodable {
    let id: String
    let title: String
    let isWriteable: Bool?
}
struct GoogleAlbumPage: Decodable {
    let albums: [GoogleAlbum]?
    let nextPageToken: String?
}
protocol GoogleAlbumTransport {
    func albumPage(pageToken: String?) async throws -> GoogleAlbumPage
    func createAlbum(title: String) async throws -> GoogleAlbum
    func getAlbum(id: String) async throws -> GoogleAlbum
}
extension GooglePersonalPhotoTransport: GoogleAlbumTransport {}

enum GoogleAlbumError: Error {
    case pending, invalid, changedAccount
}

/// A durable creation marker prevents automatic duplicate album creation after
/// an interrupted request. Ambiguous states are reconciled by listing first.
actor GoogleAlbumCoordinator {
    static let shared = GoogleAlbumCoordinator()
    private let title = "Momentra"
    private var activeOwners = Set<String>()

    func resolve(directory: URL, owner: String, transport: GoogleAlbumTransport,
                 accountIsCurrent: (String) async -> Bool) async throws -> String {
        guard !owner.isEmpty, owner.utf8.count <= 512, await accountIsCurrent(owner) else {
            throw GoogleAlbumError.changedAccount
        }
        let ownerHash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        guard activeOwners.insert(ownerHash).inserted else { throw GoogleAlbumError.pending }
        defer { activeOwners.remove(ownerHash) }
        let file = directory.appendingPathComponent(ownerHash + ".json")
        let state: Receipt?
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            guard data.count <= 8192, let value = try? JSONDecoder().decode(Receipt.self, from: data),
                  value.ownerHash == ownerHash, value.version == 1 else { throw GoogleAlbumError.pending }
            state = value
        } else { state = nil }

        if let id = state?.albumID {
            guard Self.validID(id) else { throw GoogleAlbumError.invalid }
            let existing = try await transport.getAlbum(id: id)
            guard await accountIsCurrent(owner), existing.id == id, existing.isWriteable == true else {
                throw GoogleAlbumError.pending
            }
            return id
        }

        var token: String?
        var found: GoogleAlbum?
        var reachedEnd = false
        for _ in 0..<20 {
            let page = try await transport.albumPage(pageToken: token)
            guard await accountIsCurrent(owner) else { throw GoogleAlbumError.changedAccount }
            if let album = (page.albums ?? []).first(where: { $0.title == title && $0.isWriteable == true && Self.validID($0.id) }) {
                found = album; break
            }
            guard let next = page.nextPageToken, !next.isEmpty else { reachedEnd = true; break }
            guard next != token else { throw GoogleAlbumError.pending }
            token = next
        }
        if let found {
            try save(Receipt(version: 1, ownerHash: ownerHash, state: "known", albumID: found.id), directory: directory, file: file)
            return found.id
        }

        // A previous request may have succeeded without returning a response.
        // Never silently create a second album in that ambiguous case.
        guard reachedEnd else { throw GoogleAlbumError.pending }
        if state != nil { throw GoogleAlbumError.pending }
        try save(Receipt(version: 1, ownerHash: ownerHash, state: "creating", albumID: nil), directory: directory, file: file)
        guard await accountIsCurrent(owner) else { throw GoogleAlbumError.changedAccount }
        let created = try await transport.createAlbum(title: title)
        guard await accountIsCurrent(owner), created.title == title, created.isWriteable == true,
              Self.validID(created.id) else { throw GoogleAlbumError.pending }
        try save(Receipt(version: 1, ownerHash: ownerHash, state: "known", albumID: created.id), directory: directory, file: file)
        return created.id
    }

    private func save(_ receipt: Receipt, directory: URL, file: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(receipt).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    nonisolated static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    private struct Receipt: Codable {
        let version: Int
        let ownerHash: String
        let state: String
        let albumID: String?
    }
}
