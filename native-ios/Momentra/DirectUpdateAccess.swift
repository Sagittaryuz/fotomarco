import Foundation
import Security
import UIKit

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
              let token = item.value, token.count == 64,
              token.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) }) else { return nil }
        return token
    }

    private static func endpoint(token: String, stage: String) -> URL? {
        var parts = URLComponents(string: "https://momentra-instalacao.vercel.app/api/install")
        parts?.queryItems = [URLQueryItem(name: "stage", value: stage), URLQueryItem(name: "token", value: token)]
        return parts?.url
    }

    func activate(_ url: URL) async {
        guard let token = Self.token(from: url), let metadata = Self.endpoint(token: token, stage: "metadata"), !busy else {
            message = "Não foi possível ativar as atualizações diretas."; return
        }
        busy = true; defer { busy = false }
        do {
            var request = URLRequest(url: metadata, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["version"] as? String, UpdateVersion(version) != nil,
                  Self.storeToken(token) else { throw URLError(.badServerResponse) }
            ready = true
            message = "Atualizações diretas ativadas neste iPhone."
        } catch { message = "Não foi possível ativar as atualizações diretas. Abra o link de instalação mais recente e tente novamente." }
    }

    func install(expectedVersion: String) async {
        guard !busy, let token = Self.readToken(), let metadata = Self.endpoint(token: token, stage: "metadata"),
              let manifest = Self.endpoint(token: token, stage: "manifest") else {
            message = "Ative as atualizações diretas pelo link pessoal de instalação."; return
        }
        busy = true; defer { busy = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: metadata)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["version"] as? String == expectedVersion else { throw URLError(.badServerResponse) }
            guard let encoded = manifest.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let url = URL(string: "itms-services://?action=download-manifest&url=" + encoded) else { throw URLError(.badURL) }
            let opened = await UIApplication.shared.open(url)
            if !opened { message = "Não foi possível abrir o instalador do iPhone." }
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
