import Foundation
import CryptoKit

// Callers must obtain the user's personal-use and per-photo consent before upload.
protocol PersonalPhotoTransport {
    func uploadBytes(_ jpeg: Data) async throws -> String
    func createItem(uploadToken: String, filename: String) async throws -> String
    func verifyItem(id: String) async throws -> Bool
}

private final class NoPhotoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// Tokens are injected for a single authenticated session and never written to disk.
final class GooglePersonalPhotoTransport: PersonalPhotoTransport {
    private let token: String
    private let session: URLSession
    private let base = "https://photoslibrary.googleapis.com/v1"
    private let albumID: String?

    init(token: String, albumID: String? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        self.token = token
        self.albumID = albumID
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration, delegate: NoPhotoRedirect(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    private func request(path: String, method: String, body: Data? = nil, contentType: String? = nil,
                         upload: Bool = false, limit: Int) async throws -> Data {
        guard !token.isEmpty, token.utf8.count <= 8192, !token.contains("\r"), !token.contains("\n"),
              let url = URL(string: base + path), url.scheme == "https", url.host == "photoslibrary.googleapis.com" else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if upload {
            request.setValue("raw", forHTTPHeaderField: "X-Goog-Upload-Protocol")
            request.setValue("image/jpeg", forHTTPHeaderField: "X-Goog-Upload-Content-Type")
        }
        request.httpBody = body
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              response.expectedContentLength <= Int64(limit) else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    func uploadBytes(_ jpeg: Data) async throws -> String {
        let data = try await request(path: "/uploads", method: "POST", body: jpeg,
                                     contentType: "application/octet-stream", upload: true, limit: 8192)
        guard let value = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func createItem(uploadToken: String, filename: String) async throws -> String {
        var payload: [String: Any] = ["newMediaItems": [["simpleMediaItem": ["uploadToken": uploadToken, "fileName": filename]]]]
        if let albumID { payload["albumId"] = albumID }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(path: "/mediaItems:batchCreate", method: "POST", body: body,
                                     contentType: "application/json", limit: 32768)
        let response = try JSONDecoder().decode(CreateResponse.self, from: data)
        guard response.newMediaItemResults.count == 1, let row = response.newMediaItemResults.first,
              row.status?.code == nil || row.status?.code == 0, let id = row.mediaItem?.id else {
            throw URLError(.cannotParseResponse)
        }
        return id
    }

    func verifyItem(id: String) async throws -> Bool {
        guard !id.isEmpty, id.utf8.count <= 512, id.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }) else { throw URLError(.badURL) }
        let data = try await request(path: "/mediaItems/" + id, method: "GET", limit: 32768)
        return try JSONDecoder().decode(MediaItem.self, from: data).id == id
    }

    func listAppPhotos(pageToken: String? = nil) async throws -> CloudPhotoPage {
        guard (pageToken?.utf8.count ?? 0) <= 2048 else { throw URLError(.badURL) }
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "pageSize", value: "50")]
        if let pageToken { query.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        guard let encoded = query.percentEncodedQuery else { throw URLError(.badURL) }
        let bytes = try await request(path: "/mediaItems?" + encoded, method: "GET", limit: 512 * 1024)
        return try CloudPhotoPage.parse(bytes)
    }

    func albumPage(pageToken: String?) async throws -> GoogleAlbumPage {
        guard (pageToken?.utf8.count ?? 0) <= 2048 else { throw URLError(.badURL) }
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "pageSize", value: "50")]
        if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        guard let query = components.percentEncodedQuery else { throw URLError(.badURL) }
        let data = try await request(path: "/albums?" + query, method: "GET", limit: 512 * 1024)
        return try JSONDecoder().decode(GoogleAlbumPage.self, from: data)
    }

    func createAlbum(title: String) async throws -> GoogleAlbum {
        let body = try JSONSerialization.data(withJSONObject: ["album": ["title": title]])
        let data = try await request(path: "/albums", method: "POST", body: body,
                                     contentType: "application/json", limit: 32768)
        return try JSONDecoder().decode(GoogleAlbum.self, from: data)
    }

    func getAlbum(id: String) async throws -> GoogleAlbum {
        guard GoogleAlbumCoordinator.validID(id) else { throw URLError(.badURL) }
        let data = try await request(path: "/albums/" + id, method: "GET", limit: 32768)
        return try JSONDecoder().decode(GoogleAlbum.self, from: data)
    }

    private struct MediaItem: Decodable { let id: String }
    private struct CreateResponse: Decodable {
        struct Result: Decodable {
            struct Status: Decodable { let code: Int? }
            let status: Status?
            let mediaItem: MediaItem?
        }
        let newMediaItemResults: [Result]
    }
}

enum PersonalUploadOutcome: Equatable {
    case verified(String), verificationPending(String), uncertain, failed
}

private struct PersonalUploadReceipt: Codable {
    let version: Int
    let ownerHash: String
    let captureID: UUID
    let fileHash: String
    let state: String
    let mediaID: String?
}

private final class PhotoUploadCoordination {
    static let shared = PhotoUploadCoordination()
    private let lock = NSLock()
    private var active = Set<String>()

    func begin(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active.insert(key).inserted
    }

    func end(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        active.remove(key)
    }
}

// A receipt is persisted before item creation. A crash or ambiguous response
// therefore never causes an automatic repeat upload or any local-file deletion.
actor PersonalPhotoUploader {
    private let directory: URL
    private let transport: PersonalPhotoTransport
    private let accountIsCurrent: (String) async -> Bool

    init(directory: URL, transport: PersonalPhotoTransport, accountIsCurrent: @escaping (String) async -> Bool) {
        self.directory = directory
        self.transport = transport
        self.accountIsCurrent = accountIsCurrent
    }

    func upload(jpeg: Data, captureID: UUID, owner: String, personalConsent: Bool, filename: String? = nil) async -> PersonalUploadOutcome {
        guard personalConsent, !owner.isEmpty, owner.utf8.count <= 512,
              jpeg.count >= 4, jpeg.count <= 20 * 1024 * 1024,
              jpeg.prefix(3).elementsEqual([0xff, 0xd8, 0xff]) else { return .failed }
        guard await accountIsCurrent(owner) else { return .failed }
        let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        let fileHash = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
        let key = hash + "-" + captureID.uuidString
        let file = directory.appendingPathComponent(key + ".json")
        let coordinationKey = file.standardizedFileURL.path
        guard PhotoUploadCoordination.shared.begin(coordinationKey) else { return .uncertain }
        defer { PhotoUploadCoordination.shared.end(coordinationKey) }
        let decoder = JSONDecoder()
        if FileManager.default.fileExists(atPath: file.path) {
            guard let data = try? Data(contentsOf: file), data.count <= 8192,
                  let receipt = try? decoder.decode(PersonalUploadReceipt.self, from: data),
                  receipt.version == 1, receipt.ownerHash == hash, receipt.captureID == captureID,
                  receipt.fileHash == fileHash else { return .uncertain }
            guard receipt.state == "known", let id = receipt.mediaID, Self.validID(id) else { return .uncertain }
            return await verify(id, owner: owner)
        }
        let token: String
        do { token = try await transport.uploadBytes(jpeg) } catch { return .failed }
        guard await accountIsCurrent(owner) else { return .failed }
        guard !token.isEmpty, token.utf8.count <= 8192,
              token.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { return .failed }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let creating = PersonalUploadReceipt(version: 1, ownerHash: hash, captureID: captureID, fileHash: fileHash, state: "creating", mediaID: nil)
            try JSONEncoder().encode(creating).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { return .failed }
        guard await accountIsCurrent(owner) else { return .uncertain }
        let id: String
        do { id = try await transport.createItem(uploadToken: token, filename: filename ?? captureID.uuidString + ".jpg") }
        catch { return .uncertain }
        guard Self.validID(id) else { return .uncertain }
        do {
            let known = PersonalUploadReceipt(version: 1, ownerHash: hash, captureID: captureID, fileHash: fileHash, state: "known", mediaID: id)
            try JSONEncoder().encode(known).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { return .uncertain }
        return await verify(id, owner: owner)
    }

    private func verify(_ id: String, owner: String) async -> PersonalUploadOutcome {
        guard await accountIsCurrent(owner) else { return .verificationPending(id) }
        do {
            let verified = try await transport.verifyItem(id: id)
            guard await accountIsCurrent(owner) else { return .verificationPending(id) }
            return verified ? .verified(id) : .verificationPending(id)
        }
        catch { return .verificationPending(id) }
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 512 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
