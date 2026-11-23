import Foundation

/// The Firebase ID token is supplied by the sign-in session, never by a cloud archive account.
struct BusinessAPIClient {
    enum Failure: Error { case notConfigured, invalidRequest, unauthorized, unavailable, invalidResponse }
    struct OrganizationReceipt: Decodable { let organizationId: String }
    struct InvitationReceipt: Decodable { let id: String; let expiresAt: Int64 }
    struct ProfileReceipt: Decodable { let organizationId: String; let versionId: String; let layoutJSON: String }
    struct VersionReceipt: Decodable { let versionId: String }
    struct AssetReceipt: Decodable { let assetId: String }
    struct Asset: Decodable { let mimeType: String; let base64: String }
    struct OrganizationSettings: Decodable { let id: String; let name: String; let photoAssetId: String; let contactEmail: String? }
    private let endpoint: URL
    private let transport: (URLRequest) async throws -> (Data, URLResponse)

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }

    init(endpoint: URL) throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        try self.init(endpoint: endpoint, transport: { try await session.data(for: $0) })
    }

    init(endpoint: URL, transport: @escaping (URLRequest) async throws -> (Data, URLResponse)) throws {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { throw Failure.notConfigured }
        self.endpoint = endpoint
        self.transport = transport
    }

    func createOrganization(name: String, contactEmail: String, token: String) async throws -> OrganizationReceipt {
        try await post(path: ["v1", "organizations"], values: ["name": name, "contactEmail": contactEmail], token: token)
    }

    func invite(organizationID: String, email: String, token: String) async throws -> InvitationReceipt {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "invitations"], values: ["email": email], token: token)
    }

    func accept(organizationID: String, invitationID: String, token: String) async throws -> OrganizationReceipt {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "invitations", try Self.id(invitationID), "accept"], values: [:], token: token)
    }

    func readProfile(organizationID: String, token: String) async throws -> ProfileReceipt {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "profile", "read"], values: [:], token: token)
    }

    func publishProfile(organizationID: String, layoutJSON: String, token: String) async throws -> VersionReceipt {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "profile", "publish"], values: ["layoutJSON": layoutJSON], token: token)
    }

    func uploadAsset(organizationID: String, mimeType: String, imageData: Data, token: String) async throws -> AssetReceipt {
        guard ["image/jpeg", "image/png"].contains(mimeType), !imageData.isEmpty, imageData.count <= 262144 else { throw Failure.invalidRequest }
        return try await post(path: ["v1", "organizations", try Self.id(organizationID), "assets", "upload"],
                              values: ["mimeType": mimeType, "base64": imageData.base64EncodedString()], token: token, maxBodySize: 360448)
    }

    func readAsset(organizationID: String, assetID: String, token: String) async throws -> Asset {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "assets", try Self.id(assetID), "read"], values: [:], token: token)
    }

    func readOrganization(organizationID: String, token: String) async throws -> OrganizationSettings {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "settings", "read"], values: [:], token: token)
    }

    func updateOrganization(organizationID: String, name: String, contactEmail: String,
                            photoAssetID: String, token: String) async throws -> OrganizationSettings {
        if !photoAssetID.isEmpty { _ = try Self.id(photoAssetID) }
        return try await post(path: ["v1", "organizations", try Self.id(organizationID), "settings", "update"],
                              values: ["name": name, "contactEmail": contactEmail, "photoAssetId": photoAssetID], token: token)
    }

    private func post<T: Decodable>(path: [String], values: [String: String], token: String, maxBodySize: Int = 98304) async throws -> T {
        guard !token.isEmpty, token.utf8.count <= 16384,
              token.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 }) else { throw Failure.invalidRequest }
        let body = try JSONEncoder().encode(values)
        guard body.count <= maxBodySize else { throw Failure.invalidRequest }
        var url = endpoint
        for component in path { url.appendPathComponent(component) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw Failure.unauthorized }
        guard (200...299).contains(http.statusCode), data.count <= 400000 else { throw Failure.unavailable }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw Failure.invalidResponse }
    }

    private static func id(_ value: String) throws -> String {
        guard value.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else { throw Failure.invalidRequest }
        return value
    }
}
