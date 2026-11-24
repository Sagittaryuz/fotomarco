import Foundation

/// The Firebase ID token is supplied by the sign-in session, never by a cloud archive account.
struct BusinessAPIClient {
    static func configured(bundle: Bundle = .main) -> BusinessAPIClient? {
        guard let raw = bundle.object(forInfoDictionaryKey: "PhotomarkBusinessAPI") as? String,
              !raw.contains("$"), let url = URL(string: raw) else { return nil }
        return try? BusinessAPIClient(endpoint: url)
    }
    enum Failure: Error { case notConfigured, invalidRequest, unauthorized, unavailable, invalidResponse, storageAccountChangeRequiresMigration, mailboxMismatch, mailNotConfigured }
    struct OrganizationReceipt: Decodable { let organizationId: String }
    struct InvitationReceipt: Decodable { let id: String; let expiresAt: Int64 }
    struct ProfileReceipt: Decodable { let organizationId: String; let versionId: String; let layoutJSON: String }
    struct VersionReceipt: Decodable { let versionId: String }
    struct AssetReceipt: Decodable { let assetId: String }
    struct Asset: Decodable { let mimeType: String; let base64: String }
    struct OrganizationSettings: Decodable { let id: String; let name: String; let photoAssetId: String; let contactEmail: String? }
    struct Member: Decodable, Identifiable { let userId: String; let role: String; let email: String?; let displayName: String?; let revocationPending: Bool?; var id: String { userId } }
    struct MemberList: Decodable { let members: [Member] }
    struct MemberRemoval: Decodable { let complete: Bool }
    struct CaptureReservation: Decodable { let captureId: String; let variant: String; let state: String }
    struct UploadStart: Decodable { let state: String; let nextOffset: Int64 }
    struct OrganizationSummary: Decodable, Identifiable { let id: String; let name: String; let role: String; let photoAssetId: String; let captureReady: Bool? }
    struct OrganizationList: Decodable { let organizations: [OrganizationSummary] }
    struct StorageConnection: Decodable { let connected: Bool }
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

    func myOrganizations(token: String) async throws -> OrganizationList {
        try await post(path: ["v1", "organizations", "mine"], values: [:], token: token)
    }

    func connectOneDrive(organizationID: String, refreshToken: String, token: String) async throws -> StorageConnection {
        guard !refreshToken.isEmpty, refreshToken.utf8.count <= 16384 else { throw Failure.invalidRequest }
        return try await post(path: ["v1", "organizations", try Self.id(organizationID), "storage", "onedrive", "connect"],
                              values: ["refreshToken": refreshToken], token: token, maxBodySize: 20000)
    }

    func connectGoogleMail(organizationID: String, refreshToken: String, token: String) async throws -> StorageConnection {
        guard !refreshToken.isEmpty, refreshToken.utf8.count <= 16384 else { throw Failure.invalidRequest }
        return try await post(path: ["v1", "organizations", try Self.id(organizationID), "mail", "gmail", "connect"],
                              values: ["refreshToken": refreshToken], token: token, maxBodySize: 20000)
    }

    func invite(organizationID: String, email: String, token: String) async throws -> InvitationReceipt {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "invitations"], values: ["email": email], token: token)
    }

    func listMembers(organizationID: String, token: String) async throws -> MemberList {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "members", "list"], values: [:], token: token)
    }

    func removeMember(organizationID: String, userID: String, token: String) async throws -> MemberRemoval {
        try await post(path: ["v1", "organizations", try Self.id(organizationID), "members", try Self.id(userID), "remove"], values: [:], token: token)
    }

    func reserveCapture(organizationID: String, captureID: UUID, filename: String,
                        fingerprint: CloudFileFingerprint, token: String) async throws -> CaptureReservation {
        struct Payload: Encodable { let captureId: String; let filename: String; let byteCount: Int64; let sha256: String }
        let body = try JSONEncoder().encode(Payload(captureId: captureID.uuidString, filename: filename,
                                                   byteCount: fingerprint.byteCount, sha256: fingerprint.sha256))
        return try await postBody(path: ["v1", "organizations", try Self.id(organizationID), "captures", "reserve"], body: body, token: token)
    }

    func startCaptureUpload(organizationID: String, captureID: UUID, variant: String, token: String) async throws -> UploadStart {
        guard ["original", "stamped"].contains(variant) else { throw Failure.invalidRequest }
        return try await post(path: ["v1", "organizations", try Self.id(organizationID), "captures", captureID.uuidString, variant, "start"], values: [:], token: token)
    }

    func sendCaptureChunk(organizationID: String, captureID: UUID, variant: String, offset: Int64,
                          bytes: Data, token: String) async throws -> UploadStart {
        guard ["original", "stamped"].contains(variant), offset >= 0, !bytes.isEmpty, bytes.count <= 320 * 1024 * 10 else { throw Failure.invalidRequest }
        return try await postBody(path: ["v1", "organizations", try Self.id(organizationID), "captures", captureID.uuidString, variant, "chunk"],
                                  body: bytes, token: token, maxBodySize: 320 * 1024 * 10,
                                  contentType: "application/octet-stream", uploadOffset: offset)
    }

    func verifyCapture(organizationID: String, captureID: UUID, variant: String, token: String) async throws -> UploadStart {
        guard ["original", "stamped"].contains(variant) else { throw Failure.invalidRequest }
        return try await post(path: ["v1", "organizations", try Self.id(organizationID), "captures", captureID.uuidString, variant, "verify"], values: [:], token: token)
    }

    func reconcileCapture(organizationID: String, captureID: UUID, variant: String, token: String) async throws -> UploadStart {
        guard ["original", "stamped"].contains(variant) else { throw Failure.invalidRequest }
        return try await post(path: ["v1", "organizations", try Self.id(organizationID), "captures", captureID.uuidString, variant, "reconcile"], values: [:], token: token)
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
        let body = try JSONEncoder().encode(values)
        return try await postBody(path: path, body: body, token: token, maxBodySize: maxBodySize)
    }

    private func postBody<T: Decodable>(path: [String], body: Data, token: String, maxBodySize: Int = 98304,
                                         contentType: String = "application/json", uploadOffset: Int64? = nil) async throws -> T {
        guard !token.isEmpty, token.utf8.count <= 16384,
              token.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 }) else { throw Failure.invalidRequest }
        guard body.count <= maxBodySize else { throw Failure.invalidRequest }
        var url = endpoint
        for component in path { url.appendPathComponent(component) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let uploadOffset { request.setValue(String(uploadOffset), forHTTPHeaderField: "X-Upload-Offset") }
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if http.statusCode == 409 { throw Failure.storageAccountChangeRequiresMigration }
        if http.statusCode == 412 { throw Failure.mailNotConfigured }
        if http.statusCode == 422 { throw Failure.mailboxMismatch }
        if http.statusCode == 401 || http.statusCode == 403 { throw Failure.unauthorized }
        guard (200...299).contains(http.statusCode), data.count <= 400000 else { throw Failure.unavailable }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw Failure.invalidResponse }
    }

    private static func id(_ value: String) throws -> String {
        guard value.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else { throw Failure.invalidRequest }
        return value
    }
}
