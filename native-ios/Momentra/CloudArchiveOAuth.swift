import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class CloudArchiveOAuth {
    enum Failure: LocalizedError {
        case notConfigured, busy, cancelled, invalidResponse, denied, disconnected, expired, wrongAccount, keychain, random
        case oneDriveFolderUnavailable
        case microsoftToken(Int, Int?)
        case microsoftIdentity

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "A conexão com este serviço ainda não está disponível nesta versão."
            case .busy: return "Conclua a conexão em andamento."
            case .cancelled: return "A conexão foi cancelada."
            case .invalidResponse: return "Não foi possível confirmar a conta com o serviço de armazenamento."
            case .denied: return "A permissão para armazenar arquivos do Fotomarco não foi concedida."
            case .disconnected, .expired: return "Conecte novamente a mesma conta para retomar seus envios."
            case .wrongAccount: return "A conta retornada não corresponde ao destino escolhido."
            case .keychain: return "Não foi possível acessar as credenciais. Desbloqueie o iPhone e tente novamente."
            case .random: return "Não foi possível iniciar uma conexão segura."
            case .oneDriveFolderUnavailable: return "A Microsoft autenticou a conta, mas a pasta do aplicativo não está acessível no OneDrive. Confira se o OneDrive está ativo nessa conta e tente de novo."
            case .microsoftToken(let status, let code):
                let reference = code.map { " Código Microsoft AADSTS\($0)." } ?? ""
                return "A Microsoft recusou a confirmação do login (HTTP \(status))." + reference
            case .microsoftIdentity: return "A Microsoft confirmou o login, mas não retornou a identidade da conta."
            }
        }
    }

    struct Configuration {
        let provider: CloudDeliveryPlan.Provider
        let clientID: String
        let callback: URL
        let callbackScheme: String
        let authorizeURL: URL
        let tokenURL: URL
        let identityURL: URL
        let requiredScope: String
        let scopes: String

        init(provider: CloudDeliveryPlan.Provider, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) throws {
            self.provider = provider
            let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
            let registeredSchemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            switch provider {
            case .googleDrive:
                guard let client = info["GIDClientID"] as? String,
                      client.range(of: #"^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$"#,
                                   options: .regularExpression) != nil else { throw Failure.notConfigured }
                clientID = client
                callbackScheme = client.split(separator: ".").reversed().joined(separator: ".")
                callback = URL(string: callbackScheme + ":/oauth2callback")!
                authorizeURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
                identityURL = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
                requiredScope = "https://www.googleapis.com/auth/drive.file"
                scopes = "openid email profile " + requiredScope
            case .oneDrive:
                guard let client = info["MomentraMicrosoftClientID"] as? String,
                      let clientUUID = UUID(uuidString: client) else { throw Failure.notConfigured }
                clientID = clientUUID.uuidString.lowercased()
                callbackScheme = "msauth.br.com.momentra.camera"
                callback = URL(string: callbackScheme + "://auth")!
                authorizeURL = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
                tokenURL = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!
                identityURL = URL(string: "https://graph.microsoft.com/oidc/userinfo")!
                requiredScope = "Files.ReadWrite.AppFolder"
                scopes = "openid email profile offline_access https://graph.microsoft.com/" + requiredScope
            }
            guard registeredSchemes.contains(callbackScheme) else { throw Failure.notConfigured }
        }

        func includesStorageScope(_ scope: String) -> Bool {
            scope.split(whereSeparator: \.isWhitespace).contains { granted in
                switch provider {
                case .googleDrive: return granted == requiredScope
                case .oneDrive:
                    let value = granted.lowercased()
                    return value == requiredScope.lowercased() ||
                        value == "https://graph.microsoft.com/" + requiredScope.lowercased()
                }
            }
        }
    }

    struct Credential: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    struct AuthorizedAccount {
        let destination: CloudDeliveryPlan.Destination
        let label: String
        let credential: Credential
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
        let token_type: String
        let scope: String?
    }

    private struct MicrosoftTokenError: Decodable {
        let error_codes: [Int]?
    }

    private struct Identity: Decodable {
        let sub: String
        let name: String?
        let email: String?
    }

    struct OneDriveFolder: Decodable {
        struct Parent: Decodable { let driveId: String? }
        let id: String?
        let parentReference: Parent?

        func bindings(for subject: String) -> [String] {
            let prefix = "\(subject.utf8.count):\(subject)"
            let drive = parentReference?.driveId.flatMap { validIdentifier($0) ? prefix + $0 : nil }
            let folder = id.flatMap { validIdentifier($0) ? "folder:" + prefix + $0 : nil }
            return [drive, folder].compactMap { $0 }
        }

        private func validIdentifier(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 512
        }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private let network = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    func connect(_ configuration: Configuration, presenting: UIWindow,
                 knownDestinations: Set<CloudDeliveryPlan.Destination>) async throws -> AuthorizedAccount {
        let verifier = try Self.randomParameter()
        let state = try Self.randomParameter()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var authorization = URLComponents(url: configuration.authorizeURL, resolvingAgainstBaseURL: false)!
        var query = [
            "client_id": configuration.clientID, "response_type": "code",
            "redirect_uri": configuration.callback.absoluteString, "scope": configuration.scopes,
            "code_challenge": challenge, "code_challenge_method": "S256", "state": state
        ]
        switch configuration.provider {
        case .googleDrive:
            query["access_type"] = "offline"
            query["prompt"] = "select_account consent"
        case .oneDrive:
            query["prompt"] = "select_account"
            query["response_mode"] = "query"
        }
        authorization.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = authorization.url else { throw Failure.invalidResponse }
        let browser = Browser(window: presenting)
        let callback = try await browser.open(url, scheme: configuration.callbackScheme)
        let code = try Self.authorizationCode(from: callback, expected: configuration.callback, state: state)
        let credentials = try await redeem([
            "grant_type": "authorization_code", "code": code, "code_verifier": verifier,
            "redirect_uri": configuration.callback.absoluteString
        ], configuration: configuration, previous: nil)
        return try await resolve(credentials, configuration: configuration, knownDestinations: knownDestinations)
    }

    func refresh(_ previous: Credential, configuration: Configuration,
                 destination: CloudDeliveryPlan.Destination) async throws -> AuthorizedAccount {
        let credentials = try await redeem([
            "grant_type": "refresh_token", "refresh_token": previous.refreshToken
        ], configuration: configuration, previous: previous)
        return try await resolve(credentials, configuration: configuration, knownDestinations: [destination])
    }

    static func authorizationCode(from callback: URL, expected: URL, state: String) throws -> String {
        guard let received = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let target = URLComponents(url: expected, resolvingAgainstBaseURL: false),
              received.scheme == target.scheme, received.host == target.host,
              received.port == target.port,
              received.user == nil, received.password == nil, received.fragment == nil else {
            throw Failure.invalidResponse
        }
        // Microsoft's consumer sign-in can serialize the empty callback path as a slash.
        let microsoftRoot = target.scheme == "msauth.br.com.momentra.camera" &&
            target.host == "auth" && target.percentEncodedPath.isEmpty && received.percentEncodedPath == "/"
        guard received.percentEncodedPath == target.percentEncodedPath || microsoftRoot else {
            throw Failure.invalidResponse
        }
        let parameters = Dictionary(grouping: received.queryItems ?? [], by: \.name)
        guard parameters["state"]?.count == 1, parameters["state"]?.first?.value == state else {
            throw Failure.invalidResponse
        }
        guard parameters["error"] == nil else { throw Failure.denied }
        guard parameters["code"]?.count == 1, let code = parameters["code"]?.first?.value,
              !code.isEmpty, code.utf8.count <= 4096 else { throw Failure.invalidResponse }
        return code
    }

    private func redeem(_ fields: [String: String], configuration: Configuration, previous: Credential?) async throws -> Credential {
        var parameters = fields
        parameters["client_id"] = configuration.clientID
        if configuration.provider == .oneDrive { parameters["scope"] = configuration.scopes }
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(parameters)
        let (data, response) = try await network.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.invalidResponse }
        guard status == 200 else {
            if configuration.provider == .oneDrive, previous == nil {
                let code = (try? JSONDecoder().decode(MicrosoftTokenError.self, from: data))?.error_codes?.first
                throw Failure.microsoftToken(status, code)
            }
            if status == 400 || status == 401 || status == 403 {
                throw previous == nil ? Failure.denied : Failure.expired
            }
            throw Failure.invalidResponse
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
              token.token_type.lowercased() == "bearer", token.expires_in > 0, token.expires_in <= 86400,
              let refresh = token.refresh_token ?? previous?.refreshToken,
              Self.validToken(token.access_token), Self.validToken(refresh) else { throw Failure.invalidResponse }
        if let scope = token.scope {
            guard configuration.includesStorageScope(scope) else { throw Failure.denied }
        }
        return Credential(accessToken: token.access_token, refreshToken: refresh,
                          expiresAt: Date().addingTimeInterval(token.expires_in))
    }

    private func resolve(_ credential: Credential, configuration: Configuration,
                         knownDestinations: Set<CloudDeliveryPlan.Destination>) async throws -> AuthorizedAccount {
        let identity: Identity
        do {
            identity = try await get(configuration.identityURL, token: credential.accessToken)
        } catch let error where configuration.provider == .oneDrive && !Task.isCancelled {
            if error is URLError { throw error }
            throw Failure.microsoftIdentity
        }
        guard !identity.sub.isEmpty, identity.sub.utf8.count <= 512 else { throw Failure.invalidResponse }
        let bindings: [String]
        switch configuration.provider {
        case .googleDrive:
            bindings = [identity.sub]
        case .oneDrive:
            let rootURL = URL(string: "https://graph.microsoft.com/v1.0/me/drive/special/approot")!
            do {
                let folder: OneDriveFolder = try await get(rootURL, token: credential.accessToken)
                bindings = folder.bindings(for: identity.sub)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw Failure.oneDriveFolderUnavailable
            }
            guard !bindings.isEmpty else { throw Failure.oneDriveFolderUnavailable }
        }
        let candidates = bindings.compactMap { binding in
            let hash = SHA256.hash(data: Data(binding.utf8)).map { String(format: "%02x", $0) }.joined()
            return CloudDeliveryPlan.Destination(provider: configuration.provider, accountHash: hash)
        }
        guard let destination = candidates.first(where: knownDestinations.contains) ?? candidates.first else {
            throw Failure.invalidResponse
        }
        let hash = destination.accountHash
        let rawLabel = identity.email ?? identity.name ?? String(hash.prefix(8))
        let label = rawLabel.components(separatedBy: .controlCharacters).joined().prefix(240)
        return AuthorizedAccount(destination: destination, label: label.isEmpty ? String(hash.prefix(8)) : String(label),
                                 credential: credential)
    }

    private func get<Value: Decodable>(_ url: URL, token: String) async throws -> Value {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await network.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.invalidResponse }
        if status == 401 || status == 403 { throw Failure.denied }
        guard status == 200, let value = try? JSONDecoder().decode(Value.self, from: data) else {
            throw Failure.invalidResponse
        }
        return value
    }

    private static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 32768 && value.utf8.allSatisfy { (33...126).contains($0) }
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(fields.sorted(by: { $0.key < $1.key }).map { name, value in
            let key = name.addingPercentEncoding(withAllowedCharacters: unreserved)!
            let field = value.addingPercentEncoding(withAllowedCharacters: unreserved)!
            return key + "=" + field
        }.joined(separator: "&").utf8)
    }

    private static func randomParameter() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw Failure.random }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    @MainActor
    private final class Browser: NSObject, ASWebAuthenticationPresentationContextProviding {
        let window: UIWindow
        private var session: ASWebAuthenticationSession?
        private var continuation: CheckedContinuation<URL, Error>?

        init(window: UIWindow) {
            self.window = window
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }

        func open(_ url: URL, scheme: String) async throws -> URL {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: Failure.cancelled)
                        return
                    }
                    self.continuation = continuation
                    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
                        Task { @MainActor in
                            if let callback { self?.finish(.success(callback)) }
                            else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                                self?.finish(.failure(Failure.cancelled))
                            } else { self?.finish(.failure(Failure.invalidResponse)) }
                        }
                    }
                    self.session = session
                    session.presentationContextProvider = self
                    session.prefersEphemeralWebBrowserSession = true
                    if !session.start() { finish(.failure(Failure.invalidResponse)) }
                }
            } onCancel: {
                Task { @MainActor in
                    self.session?.cancel()
                    self.finish(.failure(Failure.cancelled))
                }
            }
        }

        private func finish(_ result: Result<URL, Error>) {
            let pending = continuation
            continuation = nil
            session = nil
            pending?.resume(with: result)
        }
    }
}
