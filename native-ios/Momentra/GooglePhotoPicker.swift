import Foundation

private final class NoPickerRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct GooglePickerSession: Decodable {
    struct Polling: Decodable { let pollInterval: String; let timeoutIn: String }
    let id: String
    let pickerUri: String?
    let mediaItemsSet: Bool?
    let pollingConfig: Polling?

    var pickerURL: URL? {
        guard let value = pickerUri, value.utf8.count <= 4096, let url = URL(string: value),
              url.scheme == "https", url.host?.lowercased() == "photos.google.com",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }

    static func duration(_ value: String) -> TimeInterval? {
        guard value.hasSuffix("s"), value.utf8.count <= 24,
              let seconds = Double(value.dropLast()), seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }
}

struct GooglePickedPhoto: Decodable {
    struct File: Decodable { let baseUrl: String; let mimeType: String?; let filename: String? }
    let id: String
    let type: String
    let createTime: String?
    let mediaFile: File

    var downloadURL: URL? {
        let raw = mediaFile.baseUrl
        guard type == "PHOTO", mediaFile.mimeType?.lowercased().hasPrefix("image/") == true,
              raw.utf8.count <= 4096, let url = URL(string: raw), url.scheme == "https",
              url.host?.lowercased() == "lh3.googleusercontent.com",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        return URL(string: raw + "=d")
    }

    var creationDate: Date? {
        guard let createTime, createTime.utf8.count <= 48 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createTime) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: createTime)
    }
}

/// An authenticated, bounded client for the Google Photos Picker API.
/// Session ownership and user consent are checked by its caller.
final class GooglePhotoPickerClient {
    private let token: String
    private let session: URLSession

    init(token: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.token = token
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: NoPickerRedirect(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil, limit: Int) async throws -> Data {
        guard !token.isEmpty, token.utf8.count <= 8192, !token.contains("\r"), !token.contains("\n"),
              url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(), host == "photospicker.googleapis.com" || host == "lh3.googleusercontent.com" else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              response.expectedContentLength <= Int64(limit) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    private func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        var url = URLComponents()
        url.scheme = "https"; url.host = "photospicker.googleapis.com"; url.path = "/v1/" + path
        if !query.isEmpty { url.queryItems = query }
        guard let result = url.url else { throw URLError(.badURL) }
        return result
    }

    private func sessionPath(_ id: String) throws -> String {
        guard !id.isEmpty, id.utf8.count <= 512,
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { throw URLError(.badURL) }
        return "sessions/" + id
    }

    func create() async throws -> GooglePickerSession {
        let body = Data(#"{"pickingConfig":{"maxItemCount":"1"}}"#.utf8)
        let bytes = try await request(endpoint("sessions"), method: "POST", body: body, limit: 32768)
        let result = try JSONDecoder().decode(GooglePickerSession.self, from: bytes)
        _ = try sessionPath(result.id)
        // The caller must delete the created session even if pickerURL is invalid.
        return result
    }

    func status(id: String) async throws -> GooglePickerSession {
        let bytes = try await request(endpoint(sessionPath(id)), limit: 32768)
        let result = try JSONDecoder().decode(GooglePickerSession.self, from: bytes)
        guard result.id == id else { throw URLError(.cannotParseResponse) }
        return result
    }

    func selected(id: String) async throws -> GooglePickedPhoto? {
        _ = try sessionPath(id)
        let url = try endpoint("mediaItems", query: [URLQueryItem(name: "sessionId", value: id), URLQueryItem(name: "pageSize", value: "1")])
        let data = try await request(url, limit: 65536)
        struct Response: Decodable { let mediaItems: [GooglePickedPhoto]? }
        let items = try JSONDecoder().decode(Response.self, from: data).mediaItems ?? []
        guard items.count <= 1 else { throw URLError(.cannotParseResponse) }
        return items.first
    }

    func download(_ photo: GooglePickedPhoto) async throws -> Data {
        guard let url = photo.downloadURL else { throw URLError(.badURL) }
        return try await request(url, limit: 30 * 1024 * 1024)
    }

    func delete(id: String) async throws {
        _ = try await request(endpoint(sessionPath(id)), method: "DELETE", limit: 4096)
    }
}
