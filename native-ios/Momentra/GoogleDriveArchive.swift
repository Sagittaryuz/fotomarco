import Foundation
import CoreLocation

/// Accesses only the files created or opened by Momentra under the current drive.file grant.
final class GoogleDriveArchive {
    static let scope = "https://www.googleapis.com/auth/drive.file"

    struct Item: Decodable {
        struct Capabilities: Decodable {
            let canUntrash: Bool?
        }

        let id: String
        let name: String
        let mimeType: String
        let createdTime: String?
        let size: String?
        let sha256Checksum: String?
        let parents: [String]?
        let trashed: Bool?
        let trashedTime: String?
        let thumbnailLink: String?
        let version: String?
        let capabilities: Capabilities?
        let appProperties: [String: String]?
    }

    struct Page: Decodable {
        let files: [Item]
        let nextPageToken: String?
    }

    enum ArchiveError: LocalizedError {
        case invalidRequest, invalidResponse, integrity, insufficientStorage, http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidRequest: return "Dados inválidos para o Google Drive."
            case .invalidResponse: return "O Google Drive retornou uma resposta inválida."
            case .integrity: return "Não foi possível verificar a integridade do arquivo no Google Drive."
            case .insufficientStorage: return "Sem espaço disponível no Google Drive."
            case .http(401), .http(403): return "Confirme o acesso à conta ou verifique o espaço disponível no Google Drive."
            case .http(429): return "O Google Drive limitou as solicitações. Tente novamente mais tarde."
            case .http(507): return "Sem espaço disponível no Google Drive."
            case .http(let status): return "O Google Drive não concluiu a operação (HTTP \(status))."
            }
        }
    }

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private struct ReservedIDs: Decodable { let ids: [String] }
    private static let folderMIME = "application/vnd.google-apps.folder"
    private static let folderMarker = "momentraArchive"
    private static let fields = "id,name,mimeType,createdTime,size,sha256Checksum,parents,trashed,appProperties"
    private static let maximumPhotoSize = 200 * 1024 * 1024
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func folder(accessToken: String) async throws -> String {
        let query = "trashed = false and mimeType = '\(Self.folderMIME)' and 'root' in parents "
            + "and appProperties has { key='\(Self.folderMarker)' and value='1' }"
        let page = try await find(query, pageToken: nil, accessToken: accessToken)
        if let existing = page.files.first {
            guard Self.validID(existing.id), existing.mimeType == Self.folderMIME,
                  existing.trashed == false, existing.appProperties?[Self.folderMarker] == "1" else {
                throw ArchiveError.invalidResponse
            }
            return existing.id
        }

        let id = try await reserveFileID(accessToken: accessToken)
        let payload: [String: Any] = [
            "id": id, "name": "Momentra", "mimeType": Self.folderMIME, "parents": ["root"],
            "appProperties": [Self.folderMarker: "1"]
        ]
        var request = try request(path: "/drive/v3/files", query: ["fields": Self.fields],
                                  method: "POST", accessToken: accessToken)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let created: Item = try await decode(request)
        guard created.id == id, created.mimeType == Self.folderMIME, created.trashed == false,
              created.appProperties?[Self.folderMarker] == "1" else { throw ArchiveError.invalidResponse }
        return id
    }

    /// Persist this ID in the delivery journal before uploading bytes.
    func reserveFileID(accessToken: String) async throws -> String {
        let request = try request(path: "/drive/v3/files/generateIds", query: ["count": "1", "space": "drive"],
                                  accessToken: accessToken)
        let result: ReservedIDs = try await decode(request)
        guard result.ids.count == 1, let id = result.ids.first, Self.validID(id) else {
            throw ArchiveError.invalidResponse
        }
        return id
    }

    func upload(file: URL, id: String, folderID: String, name: String, mimeType: String,
                fingerprint: CloudFileFingerprint,
                accessToken: String, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        guard Self.validID(id), Self.validID(folderID), !name.isEmpty, name.utf8.count <= 255,
              ["image/jpeg", "image/heic", "image/heif"].contains(mimeType) else {
            throw ArchiveError.invalidRequest
        }
        guard try CloudFileFingerprint.read(file) == fingerprint else { throw ArchiveError.integrity }
        do {
            try await verify(id: id, folderID: folderID, name: name, mimeType: mimeType,
                             fingerprint: fingerprint, accessToken: accessToken)
            return id
        } catch ArchiveError.http(404) {
            // The reserved ID has not been used yet for the current account.
        }

        let boundary = "Momentra-\(UUID().uuidString)"
        let metadata: [String: Any] = [
            "id": id, "name": name, "mimeType": mimeType, "parents": [folderID],
            "appProperties": ["momentraArchivePhoto": "1"]
        ]
        let multipart = try makeMultipart(file: file, metadata: metadata, mimeType: mimeType, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: multipart) }

        var request = try request(path: "/upload/drive/v3/files", query: ["uploadType": "multipart", "fields": "id"],
                                  method: "POST", accessToken: accessToken)
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let delegate = progress.map { CloudUploadDelegate(progress: $0) }
        let (data, response) = try await session.upload(for: request, fromFile: multipart, delegate: delegate)
        do { try Self.check(response, body: data) }
        catch ArchiveError.http(409) {
            // A prior attempt can have reached Drive even though its response was lost.
        }
        try await verify(id: id, folderID: folderID, name: name, mimeType: mimeType,
                         fingerprint: fingerprint, accessToken: accessToken)
        return id
    }

    func list(pageToken: String? = nil, accessToken: String) async throws -> Page {
        // A gallery read does not create folders. The marker also keeps captures
        // visible if multiple devices provision a Momentra folder concurrently.
        try await find("trashed = false and appProperties has { key='momentraArchivePhoto' and value='1' }",
                       pageToken: pageToken, accessToken: accessToken, additionalFields: ",thumbnailLink,version")
    }

    func listTrash(pageToken: String? = nil, accessToken: String) async throws -> Page {
        try await find("trashed = true and appProperties has { key='momentraArchivePhoto' and value='1' }",
                       pageToken: pageToken, accessToken: accessToken, additionalFields: ",trashedTime,capabilities(canUntrash),thumbnailLink,version")
    }

    static func validatedThumbnailURL(_ value: String) -> URL? {
        guard (1...4096).contains(value.utf8.count), let url = URL(string: value),
              url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.fragment == nil, let host = url.host?.lowercased() else { return nil }
        let googleImageHost = host.range(of: #"^lh[0-9]+\.googleusercontent\.com$"#, options: .regularExpression) != nil
        guard googleImageHost || host == "drive.google.com" || host == "drive.googleusercontent.com" else { return nil }
        return url
    }

    func thumbnailLink(id: String, accessToken: String) async throws -> String? {
        guard Self.validID(id) else { throw ArchiveError.invalidRequest }
        struct Metadata: Decodable { let thumbnailLink: String? }
        let lookup = try request(path: "/drive/v3/files/\(id)", query: ["fields": "thumbnailLink"], accessToken: accessToken)
        let metadata: Metadata = try await decode(lookup)
        return metadata.thumbnailLink
    }

    func mapLocation(id: String, accessToken: String) async throws -> CLLocationCoordinate2D? {
        guard Self.validID(id) else { throw ArchiveError.invalidRequest }
        struct Metadata: Decodable {
            struct Image: Decodable { struct Location: Decodable { let latitude: Double?; let longitude: Double? }; let location: Location? }
            let imageMediaMetadata: Image?
        }
        let lookup = try request(path: "/drive/v3/files/\(id)",
            query: ["fields": "imageMediaMetadata(location(latitude,longitude))"], accessToken: accessToken)
        let metadata: Metadata = try await decode(lookup)
        guard let lat = metadata.imageMediaMetadata?.location?.latitude,
              let lon = metadata.imageMediaMetadata?.location?.longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    /// The URL came from Drive's read-only thumbnailLink field. Keep the bearer on Google's
    /// image hosts and use the same no-redirect session used for Drive requests.
    func thumbnail(link: String, accessToken: String) async throws -> Data? {
        guard let url = Self.validatedThumbnailURL(link) else { return nil }
        guard (1...8192).contains(accessToken.utf8.count),
              accessToken.utf8.allSatisfy({ (33...126).contains($0) }) else { throw ArchiveError.invalidRequest }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 || http.statusCode == 410 {
            return nil
        }
        try Self.check(response)
        let limit = 1_048_576
        guard response.mimeType?.lowercased().hasPrefix("image/") == true,
              response.expectedContentLength <= limit else { throw ArchiveError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw ArchiveError.invalidResponse }
            data.append(byte)
        }
        guard !data.isEmpty else { throw ArchiveError.invalidResponse }
        return data
    }

    func download(id: String, accessToken: String) async throws -> Data {
        let location = try await downloadFile(id: id, accessToken: accessToken)
        defer { try? FileManager.default.removeItem(at: location) }
        return try Data(contentsOf: location)
    }

    func trashPhoto(id: String, name: String, accessToken: String) async throws {
        guard Self.validID(id), CloudArchiveFilename(name) != nil else { throw ArchiveError.invalidRequest }
        let path = "/drive/v3/files/\(id)"
        let query = ["fields": Self.fields]
        let check = try request(path: path, query: query, accessToken: accessToken)
        let existing: Item = try await decode(check)
        guard existing.id == id, existing.name == name, existing.mimeType.hasPrefix("image/"),
              existing.appProperties?["momentraArchivePhoto"] == "1" else { throw ArchiveError.integrity }
        if existing.trashed == true { return }
        var update = try request(path: path, query: query, method: "PATCH", accessToken: accessToken)
        update.setValue("application/json", forHTTPHeaderField: "Content-Type")
        update.httpBody = Data(#"{"trashed":true}"#.utf8)
        let result: Item = try await decode(update)
        guard result.id == id, result.trashed == true else { throw ArchiveError.invalidResponse }
    }

    /// Updates metadata by immutable ID only when the app marker and version match.
    func renamePhoto(id: String, from oldName: String, to newName: String, accessToken: String) async throws {
        guard Self.validID(id), let old = CloudArchiveFilename(oldName), let new = CloudArchiveFilename(newName),
              old.captureID == new.captureID, old.isOriginal == new.isOriginal,
              (oldName as NSString).pathExtension.lowercased() == (newName as NSString).pathExtension.lowercased() else { throw ArchiveError.invalidRequest }
        let path = "/drive/v3/files/\(id)", query = ["fields": Self.fields]
        let check = try request(path: path, query: query, accessToken: accessToken)
        let (data, response) = try await session.data(for: check)
        try Self.check(response, body: data)
        let existing = try JSONDecoder().decode(Item.self, from: data)
        guard existing.id == id, existing.mimeType.hasPrefix("image/"), existing.trashed == false,
              existing.appProperties?["momentraArchivePhoto"] == "1" else { throw ArchiveError.integrity }
        if existing.name == newName { return }
        guard existing.name == oldName, let eTag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"), !eTag.isEmpty else { throw ArchiveError.integrity }
        var update = try request(path: path, query: query, method: "PATCH", accessToken: accessToken)
        update.setValue("application/json", forHTTPHeaderField: "Content-Type")
        update.setValue(eTag, forHTTPHeaderField: "If-Match")
        update.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let result: Item = try await decode(update)
        guard result.id == id, result.name == newName, result.trashed == false,
              result.appProperties?["momentraArchivePhoto"] == "1", result.size == existing.size,
              result.parents == existing.parents, result.sha256Checksum == existing.sha256Checksum else { throw ArchiveError.integrity }
        let verified: Item = try await decode(check)
        guard verified.id == id, verified.name == newName, verified.trashed == false,
              verified.appProperties?["momentraArchivePhoto"] == "1", verified.size == existing.size,
              verified.parents == existing.parents, verified.sha256Checksum == existing.sha256Checksum else { throw ArchiveError.integrity }
    }

    func restorePhoto(id: String, name: String, accessToken: String) async throws {
        guard Self.validID(id), CloudArchiveFilename(name) != nil else { throw ArchiveError.invalidRequest }
        let path = "/drive/v3/files/\(id)"
        let query = ["fields": Self.fields + ",capabilities(canUntrash)"]
        let existing: Item = try await decode(request(path: path, query: query, accessToken: accessToken))
        guard existing.id == id, existing.name == name, existing.mimeType.hasPrefix("image/"),
              existing.appProperties?["momentraArchivePhoto"] == "1" else { throw ArchiveError.integrity }
        if existing.trashed == false { return }
        guard existing.trashed == true, existing.capabilities?.canUntrash == true else {
            throw ArchiveError.invalidRequest
        }
        var update = try request(path: path, query: query, method: "PATCH", accessToken: accessToken)
        update.setValue("application/json", forHTTPHeaderField: "Content-Type")
        update.httpBody = Data(#"{"trashed":false}"#.utf8)
        let result: Item = try await decode(update)
        guard result.id == id, result.trashed == false else { throw ArchiveError.invalidResponse }
    }

    private func find(_ filter: String, pageToken: String?, accessToken: String,
                      additionalFields: String = "") async throws -> Page {
        var query = ["q": filter, "pageSize": "100", "spaces": "drive", "orderBy": "createdTime desc",
                     "fields": "nextPageToken,files(\(Self.fields)\(additionalFields))"]
        if let pageToken { query["pageToken"] = pageToken }
        let request = try request(path: "/drive/v3/files", query: query, accessToken: accessToken)
        return try await decode(request)
    }

    func verify(id: String, folderID: String, name: String, mimeType: String,
                fingerprint: CloudFileFingerprint, accessToken: String) async throws {
        guard Self.validID(id), Self.validID(folderID) else { throw ArchiveError.invalidRequest }
        let request = try request(path: "/drive/v3/files/\(id)", query: ["fields": Self.fields], accessToken: accessToken)
        let item: Item = try await decode(request)
        guard item.id == id, item.name == name, item.mimeType == mimeType, item.trashed == false,
              item.parents?.contains(folderID) == true, item.size.flatMap({ Int64($0) }) == fingerprint.byteCount else {
            throw ArchiveError.integrity
        }
        if let sha256 = item.sha256Checksum {
            guard sha256.lowercased() == fingerprint.sha256 else { throw ArchiveError.integrity }
        } else {
            let location = try await downloadFile(id: id, accessToken: accessToken)
            defer { try? FileManager.default.removeItem(at: location) }
            guard try CloudFileFingerprint.read(location) == fingerprint else { throw ArchiveError.integrity }
        }
    }

    /// The caller owns the temporary file and must remove it after use.
    func downloadFile(id: String, accessToken: String, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard Self.validID(id) else { throw ArchiveError.invalidRequest }
        let request = try request(path: "/drive/v3/files/\(id)", query: ["alt": "media"], accessToken: accessToken)
        let observer = progress.map { ShareDownloadProgress(report: $0) }
        let (location, response) = try await session.download(for: request, delegate: observer)
        do {
            try Self.check(response)
            let bytes = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0, bytes <= Self.maximumPhotoSize else { throw ArchiveError.invalidResponse }
            return location
        } catch {
            try? FileManager.default.removeItem(at: location)
            throw error
        }
    }

    private func makeMultipart(file: URL, metadata: [String: Any], mimeType: String, boundary: String) throws -> URL {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let prefix = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        try prefix.write(to: location, options: .completeFileProtectionUntilFirstUserAuthentication)
        do {
            let output = try FileHandle(forWritingTo: location)
            defer { try? output.close() }
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            try output.seekToEnd()
            try output.write(contentsOf: JSONSerialization.data(withJSONObject: metadata))
            try output.write(contentsOf: Data("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
            var count = 0
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                count += chunk.count
                guard count <= Self.maximumPhotoSize else { throw ArchiveError.integrity }
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return location
        } catch {
            try? FileManager.default.removeItem(at: location)
            throw error
        }
    }

    private func request(path: String, query: [String: String] = [:], method: String = "GET",
                         accessToken: String) throws -> URLRequest {
        guard (1...8192).contains(accessToken.utf8.count),
              accessToken.utf8.allSatisfy({ (33...126).contains($0) }) else { throw ArchiveError.invalidRequest }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = path
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw ArchiveError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        return request
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (bytes, response) = try await session.bytes(for: request)
        try Self.check(response)
        let limit = 1_048_576
        guard response.expectedContentLength <= limit else { throw ArchiveError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw ArchiveError.invalidResponse }
            data.append(byte)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func check(_ response: URLResponse, body: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw ArchiveError.invalidResponse }
        guard !(200...299).contains(http.statusCode) else { return }
        if http.statusCode == 403, let body, body.count <= 65_536,
           let error = try? JSONDecoder().decode(DriveError.self, from: body),
           error.error.errors.contains(where: { $0.reason == "storageQuotaExceeded" }) {
            throw ArchiveError.insufficientStorage
        }
        throw ArchiveError.http(http.statusCode)
    }

    private struct DriveError: Decodable {
        struct Details: Decodable {
            struct Violation: Decodable { let reason: String }
            let errors: [Violation]
        }
        let error: Details
    }

    private static func validID(_ id: String) -> Bool {
        (1...256).contains(id.utf8.count) && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
