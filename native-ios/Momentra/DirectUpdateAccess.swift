import Foundation
import Security
import UIKit
import Darwin

enum UpdateCloseReadiness {
    static func allowsClose(capturing: Bool, switching: Bool, recording: Bool, finishing: Bool,
                            processingVideos: Int, processingPhotos: Int = 0, cloudBusy: Bool) -> Bool {
        !capturing && !switching && !recording && !finishing && processingVideos == 0 && processingPhotos == 0 && !cloudBusy
    }
}

@MainActor
final class DirectUpdateAccess: ObservableObject {
    static let shared = DirectUpdateAccess()
    private static let service = "br.com.momentra.camera.updates"
    private static let account = "installer-token"
    @Published private(set) var ready: Bool
    @Published private(set) var busy = false
    @Published var message: String?

    private init() { ready = Self.readToken() != nil }

    static func token(from url: URL) -> String? {
        guard url.scheme == "momentra", url.host == "updates", url.path == "/activate",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.count == 1, let item = parts.queryItems?.first, item.name == "token",
              let token = item.value, validToken(token) else { return nil }
        return token
    }

    private static func validToken(_ token: String) -> Bool {
        token.count == 64 && token.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (97...102).contains($0.value) }
    }

    static func manifestURL(_ raw: String) -> URL? {
        guard let parts = URLComponents(string: raw), parts.scheme == "https",
              parts.host == "momentra-instalacao.vercel.app", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.path == "/api/install", let items = parts.queryItems, items.count == 2,
              items.contains(where: { $0.name == "stage" && $0.value == "manifest" }),
              let ticket = items.first(where: { $0.name == "ticket" })?.value,
              ticket.range(of: #"^[0-9]{13}\.[0-9a-f]{32}\.[0-9a-f]{64}$"#, options: .regularExpression) != nil else { return nil }
        return parts.url
    }

    private static func endpoint(token: String, stage: String) -> URL? {
        var parts = URLComponents(string: "https://momentra-instalacao.vercel.app/api/install")
        parts?.queryItems = [URLQueryItem(name: "stage", value: stage), URLQueryItem(name: "token", value: token)]
        return parts?.url
    }

    func activate(_ url: URL) async {
        guard let token = Self.token(from: url), let metadata = Self.endpoint(token: token, stage: "activate"), !busy else {
            message = "Não foi possível ativar as atualizações diretas."; return
        }
        busy = true; defer { busy = false }
        do {
            var request = URLRequest(url: metadata, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let deviceToken = object["deviceToken"] as? String, Self.validToken(deviceToken),
                  Self.storeToken(deviceToken) else { throw URLError(.badServerResponse) }
            ready = true
            message = "Atualizações diretas ativadas neste iPhone."
        } catch { message = "Não foi possível ativar as atualizações diretas. Abra o link de instalação mais recente e tente novamente." }
    }

    func publishedVersion() async throws -> String? {
        guard let token = Self.readToken() else { return nil }
        return try await publishedRelease(token: token).version
    }

    private func publishedRelease(token: String) async throws -> (version: String, manifest: URL) {
        let issueURL = URL(string: "https://momentra-instalacao.vercel.app/api/install?stage=issue")!
        var request = URLRequest(url: issueURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4096,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String, UpdateVersion(version) != nil,
              let raw = object["manifest"] as? String,
              let manifest = Self.manifestURL(raw) else { throw URLError(.badServerResponse) }
        return (version, manifest)
    }

    func install(expectedVersion: String, canClose: @escaping @MainActor () -> Bool) async {
        guard !busy else { return }
        guard let token = Self.readToken() else {
            message = "Ative as atualizações diretas pelo link pessoal de instalação."; return
        }
        guard canClose() else {
            message = "Aguarde a conclusão da captura ou do envio antes de atualizar."; return
        }
        message = nil
        busy = true; defer { busy = false }
        do {
            let release = try await publishedRelease(token: token)
            guard release.version == expectedVersion else { throw URLError(.badServerResponse) }
            let manifest = release.manifest
            guard let encoded = manifest.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let url = URL(string: "itms-services://?action=download-manifest&url=" + encoded) else { throw URLError(.badURL) }
            guard canClose() else {
                message = "Aguarde a conclusão da captura ou do envio antes de atualizar."
                return
            }
            let opened = await UIApplication.shared.open(url)
            if opened {
                guard canClose() else {
                    message = "A instalação foi solicitada. Aguarde a conclusão da captura ou do envio."
                    return
                }
                // Only leave after iOS accepts the installer request. The system
                // still controls installation and may ask for confirmation.
                exit(EXIT_SUCCESS)
            } else { message = "Não foi possível abrir o instalador do iPhone." }
        } catch { message = "O instalador ainda não está disponível para essa versão. Tente novamente mais tarde." }
    }

    private static func readToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func storeToken(_ token: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
