import Foundation
import CoreLocation

/// Operates only in the app folder of the OneDrive selected by the supplied token.
struct OneDriveArchive {
    static let scope = "Files.ReadWrite.AppFolder"

    struct Item: Identifiable {
        let id: String
        let name: String
        let date: Date?
        let revision: String?
        let captureDate: Date?
    }

    struct Page {
        let items: [Item]
        let nextPage: String?
    }

    enum Failure: LocalizedError {
        case invalidResponse
        case invalidName
        case integrity
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Resposta inválida do OneDrive."
            case .invalidName: return "Nome de arquivo inválido para o OneDrive."
            case .integrity: return "O arquivo no OneDrive não pôde ser confirmado. A cópia local foi preservada."
            case .http(401), .http(403): return "A conta precisa autorizar o acesso à pasta do aplicativo no OneDrive."
            case .http(404): return "Pasta ou arquivo indisponível no OneDrive."
            case .http(507): return "Sem espaço disponível no OneDrive."
            case .http(429): return "O OneDrive limitou temporariamente os envios. Tente novamente mais tarde."
            case .http(let code): return "O OneDrive respondeu com o código \(code)."
            }
        }
    }

    private struct DriveItem: Decodable {
        struct Folder: Decodable {}
        struct File: Decodable {}
        struct Parent: Decodable { let id: String? }
        struct Photo: Decodable { let takenDateTime: String? }
        let id: String
        let name: String
        let size: Int64?
        let createdDateTime: String?
        let eTag: String?
        let parentReference: Parent?
        let folder: Folder?
        let file: File?
        let photo: Photo?
    }

    private struct Listing: Decodable {
        let value: [DriveItem]
        let nextLink: String?
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }

    private static let graph = URL(string: "https://graph.microsoft.com/v1.0/me/drive")!
    private static let fields = URLQueryItem(name: "$select",
        value: "id,name,size,file,folder,parentReference,createdDateTime,eTag,photo")
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// Reconcile by deterministic path on all retries, including after an ambiguous PUT.
    /// Only return the ID after verifying the server's file bytes.
    func upload(_ file: URL, name: String, fingerprint: CloudFileFingerprint,
                accessToken: String, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        guard Self.validName(name) else { throw Failure.invalidName }
        guard try CloudFileFingerprint.read(file) == fingerprint else { throw Failure.integrity }
        let folder = try await folderID(accessToken: accessToken)
        if let existing = try await item(named: name, in: folder, accessToken: accessToken) {
            try await check(existing, name: name, folder: folder, fingerprint: fingerprint, accessToken: accessToken)
            return existing.id
        }

        let url = try Self.query(path(name: name, in: folder).appendingPathComponent("content"),
            items: [URLQueryItem(name: "@microsoft.graph.conflictBehavior", value: "fail")])
        var request = try authorizedRequest(url, accessToken: accessToken)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let delegate = progress.map { CloudUploadDelegate(progress: $0) }
        let (data, response) = try await Self.session.upload(for: request, fromFile: file, delegate: delegate)
        let status = try Self.status(response)
        let uploadedID: String?
        switch status {
        case 200, 201:
            let uploaded = try JSONDecoder().decode(DriveItem.self, from: data)
            guard uploaded.name == name, Self.validID(uploaded.id) else { throw Failure.integrity }
            uploadedID = uploaded.id
        case 409, 412:
            uploadedID = nil
        default:
            throw Failure.http(status)
        }
        guard let stored = try await item(named: name, in: folder, accessToken: accessToken),
              uploadedID == nil || uploadedID == stored.id else { throw Failure.integrity }
        try await check(stored, name: name, folder: folder, fingerprint: fingerprint, accessToken: accessToken)
        return stored.id
    }

    func verify(id: String, name: String, fingerprint: CloudFileFingerprint,
                accessToken: String) async throws {
        guard Self.validID(id), Self.validName(name) else { throw Failure.integrity }
        let folder = try await folderID(accessToken: accessToken)
        guard let stored = try await item(named: name, in: folder, accessToken: accessToken),
              stored.id == id else { throw Failure.integrity }
        try await check(stored, name: name, folder: folder, fingerprint: fingerprint, accessToken: accessToken)
    }

    func trashPhoto(id: String, name: String, accessToken: String) async throws {
        guard Self.validID(id), Self.validName(name) else { throw Failure.invalidName }
        let folder = try await folderID(accessToken: accessToken)
        let url = itemURL(id)
        let fields = URLQueryItem(name: "$select", value: "id,name,file,folder,parentReference,eTag")
        let item = try JSONDecoder().decode(DriveItem.self,
            from: await get(Self.query(url, items: [fields]), accessToken: accessToken))
        guard item.id == id, item.name == name, item.file != nil, item.folder == nil,
              item.parentReference?.id == folder, let eTag = item.eTag, !eTag.isEmpty else {
            throw Failure.integrity
        }
        var request = try authorizedRequest(url, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue(eTag, forHTTPHeaderField: "If-Match")
        let (_, response) = try await Self.session.data(for: request)
        let status = try Self.status(response)
        guard status == 204 || status == 404 else { throw Failure.http(status) }
    }

    /// Renames only an existing app-owned item, preserving its immutable ID and bytes.
    func renamePhoto(id: String, from oldName: String, to newName: String, accessToken: String,
                     transport: ((URLRequest) async throws -> (Data, URLResponse))? = nil) async throws {
        guard Self.validID(id), Self.validName(oldName), Self.validName(newName),
              let old = CloudArchiveFilename(oldName), let new = CloudArchiveFilename(newName),
              old.captureID == new.captureID, old.isOriginal == new.isOriginal,
              (oldName as NSString).pathExtension.lowercased() == (newName as NSString).pathExtension.lowercased() else { throw Failure.invalidName }
        let send: (URLRequest) async throws -> (Data, URLResponse) = transport ?? { try await Self.session.data(for: $0) }
        func read(_ url: URL) async throws -> DriveItem {
            let (data, response) = try await send(authorizedRequest(url, accessToken: accessToken))
            let status = try Self.status(response)
            guard status == 200 else { throw Failure.http(status) }
            return try JSONDecoder().decode(DriveItem.self, from: data)
        }
        let rootURL = Self.graph.appendingPathComponent("special").appendingPathComponent("approot")
        let root = try await read(rootURL)
        guard root.folder != nil, Self.validID(root.id) else { throw Failure.integrity }
        let folder = root.id, url = itemURL(id)
        let item = try await read(Self.query(url, items: [Self.fields]))
        guard item.id == id, item.file != nil, item.folder == nil, item.parentReference?.id == folder else { throw Failure.integrity }
        if item.name == newName { return }
        guard item.name == oldName, let eTag = item.eTag, !eTag.isEmpty else { throw Failure.integrity }
        let namedURL = path(name: newName, in: folder).deletingLastPathComponent().appendingPathComponent(newName)
        do {
            let conflict = try await read(Self.query(namedURL, items: [Self.fields]))
            if conflict.id != id { throw Failure.integrity }
        } catch Failure.http(404) { /* available */ }
        var update = try authorizedRequest(url, accessToken: accessToken)
        update.httpMethod = "PATCH"
        update.setValue(eTag, forHTTPHeaderField: "If-Match")
        update.setValue("application/json", forHTTPHeaderField: "Content-Type")
        update.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (_, response) = try await send(update)
        guard try Self.status(response) == 200 else { throw Failure.http(try Self.status(response)) }
        let checked = try await read(Self.query(url, items: [Self.fields]))
        guard checked.id == id, checked.name == newName, checked.file != nil, checked.folder == nil,
              checked.parentReference?.id == folder, checked.size == item.size else { throw Failure.integrity }
    }

    func list(accessToken: String, nextPage: String? = nil) async throws -> Page {
        let folder = try await folderID(accessToken: accessToken)
        let children = itemURL(folder).appendingPathComponent("children")
        let url: URL
        if let nextPage {
            guard let next = Self.paginationURL(nextPage, folder: folder) else { throw Failure.invalidResponse }
            url = next
        } else {
            url = try Self.query(children, items: [Self.fields, URLQueryItem(name: "$top", value: "100")])
        }
        let data = try await get(url, accessToken: accessToken)
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        guard listing.value.count <= 100 else { throw Failure.invalidResponse }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        let items = listing.value.compactMap { item -> Item? in
            guard item.file != nil, item.folder == nil, item.parentReference?.id == folder,
                  Self.validID(item.id), Self.validName(item.name) else { return nil }
            let date = item.createdDateTime.flatMap { fractional.date(from: $0) ?? standard.date(from: $0) }
            let captured = Self.takenDate(item.photo?.takenDateTime)
            return Item(id: item.id, name: item.name, date: date, revision: item.eTag, captureDate: captured)
        }
        let next = listing.nextLink.flatMap { Self.paginationURL($0, folder: folder)?.absoluteString }
        if listing.nextLink != nil && next == nil { throw Failure.invalidResponse }
        return Page(items: items, nextPage: next)
    }

    static func takenDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle().parse(value))
    }

    /// The caller owns the temporary file and must remove it after use.
    func download(id: String, accessToken: String) async throws -> URL {
        guard Self.validID(id) else { throw Failure.invalidResponse }
        let folder = try await folderID(accessToken: accessToken)
        let data = try await get(Self.query(itemURL(id), items: [Self.fields]), accessToken: accessToken)
        let item = try JSONDecoder().decode(DriveItem.self, from: data)
        guard item.id == id, item.file != nil, item.folder == nil, item.parentReference?.id == folder,
              let size = item.size, size > 0, size <= 200 * 1024 * 1024 else {
            throw Failure.invalidResponse
        }
        return try await content(id: id, byteCount: size, accessToken: accessToken)
    }

    private func folderID(accessToken: String) async throws -> String {
        let url = Self.graph.appendingPathComponent("special").appendingPathComponent("approot")
        let data = try await get(url, accessToken: accessToken)
        let item = try JSONDecoder().decode(DriveItem.self, from: data)
        guard item.folder != nil, Self.validID(item.id) else { throw Failure.invalidResponse }
        return item.id
    }

    private func itemURL(_ id: String) -> URL {
        Self.graph.appendingPathComponent("items").appendingPathComponent(id)
    }

    func thumbnail(id: String, accessToken: String) async throws -> Data? {
        guard Self.validID(id) else { throw Failure.invalidResponse }
        let url = itemURL(id).appendingPathComponent("thumbnails").appendingPathComponent("0")
            .appendingPathComponent("medium").appendingPathComponent("content")
        let (data, response) = try await Self.session.data(for: authorizedRequest(url, accessToken: accessToken))
        let status = try Self.status(response)
        if status == 404 { return nil }
        if status == 200 { return data.count <= 2_000_000 ? data : nil }
        guard status == 302, let response = response as? HTTPURLResponse,
              let location = response.value(forHTTPHeaderField: "Location"),
              let target = URL(string: location), Self.secureURL(target) else { throw Failure.http(status) }
        let (thumbnail, result) = try await Self.session.data(from: target)
        guard try Self.status(result) == 200, thumbnail.count <= 2_000_000 else { return nil }
        return thumbnail
    }

    func mapLocation(id: String, accessToken: String) async throws -> CLLocationCoordinate2D? {
        guard Self.validID(id) else { throw Failure.invalidResponse }
        struct Metadata: Decodable { struct Location: Decodable { let latitude: Double?; let longitude: Double? }; let location: Location? }
        let url = try Self.query(itemURL(id), items: [.init(name: "$select", value: "location")])
        let metadata = try JSONDecoder().decode(Metadata.self, from: await get(url, accessToken: accessToken))
        guard let lat = metadata.location?.latitude, let lon = metadata.location?.longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private func path(name: String, in folder: String) -> URL {
        Self.graph.appendingPathComponent("items").appendingPathComponent(folder + ":")
            .appendingPathComponent(name + ":")
    }

    private func item(named name: String, in folder: String, accessToken: String) async throws -> DriveItem? {
        let url = path(name: name, in: folder).deletingLastPathComponent().appendingPathComponent(name)
        do {
            let data = try await get(Self.query(url, items: [Self.fields]), accessToken: accessToken)
            return try JSONDecoder().decode(DriveItem.self, from: data)
        } catch Failure.http(404) {
            return nil
        }
    }

    private func check(_ item: DriveItem, name: String, folder: String,
                       fingerprint: CloudFileFingerprint, accessToken: String) async throws {
        guard Self.validID(item.id), item.name == name, item.file != nil, item.folder == nil,
              item.parentReference?.id == folder, item.size == fingerprint.byteCount else { throw Failure.integrity }
        let downloaded = try await content(id: item.id, byteCount: fingerprint.byteCount, accessToken: accessToken)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        guard try CloudFileFingerprint.read(downloaded) == fingerprint else { throw Failure.integrity }
    }

    private func content(id: String, byteCount: Int64, accessToken: String) async throws -> URL {
        let request = try authorizedRequest(itemURL(id).appendingPathComponent("content"), accessToken: accessToken)
        let (temporary, response) = try await Self.session.download(for: request)
        let status = try Self.status(response)
        if status == 200 { return try Self.checkedFile(temporary, byteCount: byteCount) }
        try? FileManager.default.removeItem(at: temporary)
        guard status == 302, let response = response as? HTTPURLResponse,
              let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location), Self.secureURL(url) else { throw Failure.http(status) }

        // Graph supplies a short-lived, preauthenticated URL. Never forward the access token.
        let (download, downloadResponse) = try await Self.session.download(from: url)
        guard let http = downloadResponse as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: download)
            throw Failure.invalidResponse
        }
        return try Self.checkedFile(download, byteCount: byteCount)
    }

    private static func checkedFile(_ url: URL, byteCount: Int64) throws -> URL {
        do {
            let length = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let length, Int64(length) == byteCount else { throw Failure.integrity }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func get(_ url: URL, accessToken: String) async throws -> Data {
        let (data, response) = try await Self.session.data(for: authorizedRequest(url, accessToken: accessToken))
        let status = try Self.status(response)
        guard status == 200 else { throw Failure.http(status) }
        return data
    }

    private func authorizedRequest(_ url: URL, accessToken: String) throws -> URLRequest {
        guard Self.secureURL(url), url.host?.lowercased() == "graph.microsoft.com",
              !accessToken.isEmpty else { throw Failure.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        return request
    }

    private static func query(_ url: URL, items: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw Failure.invalidResponse }
        components.queryItems = items
        guard let result = components.url else { throw Failure.invalidResponse }
        return result
    }

    private static func status(_ response: URLResponse) throws -> Int {
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        return response.statusCode
    }

    private static func secureURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil &&
            (url.port == nil || url.port == 443) && url.fragment == nil
    }

    private static func paginationURL(_ value: String, folder: String) -> URL? {
        guard value.utf8.count <= 8192, let url = URL(string: value), secureURL(url),
              url.host?.lowercased() == "graph.microsoft.com",
              url.path.hasPrefix("/v1.0/"), url.path.hasSuffix("/items/" + folder + "/children") else { return nil }
        return url
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 512 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) ||
                $0 == 33 || $0 == 45 || $0 == 95
        }
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 240 && name != "." && name != ".." &&
            !name.hasSuffix(".") && name.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) ||
                    $0 == 32 || $0 == 45 || $0 == 46 || $0 == 95
            }
    }
}
