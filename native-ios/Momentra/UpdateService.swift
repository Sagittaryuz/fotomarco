import Foundation

struct UpdateVersion: Comparable {
    let components: [Int]

    init?(_ value: String) {
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isNumber) }),
              let major = Int(pieces[0]), let minor = Int(pieces[1]), let patch = Int(pieces[2]) else { return nil }
        components = [major, minor, patch]
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

struct UpdateRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool

    var version: UpdateVersion? {
        let prefix = "native-ios-v"
        guard !draft, !prerelease, tag_name.hasPrefix(prefix) else { return nil }
        return UpdateVersion(String(tag_name.dropFirst(prefix.count)))
    }
}

@MainActor
final class UpdateService: ObservableObject {
    static let releasesURL = URL(string: "https://github.com/Sagittaryuz/momentra/releases")!
    private static let apiURL = URL(string: "https://api.github.com/repos/Sagittaryuz/momentra/releases?per_page=30")!
    @Published private(set) var availableVersion: String?
    @Published private(set) var status: String?
    @Published private(set) var checking = false
    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        guard let currentString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let current = UpdateVersion(currentString) else {
            status = "Não foi possível identificar a versão instalada."
            return
        }
        do {
            let newest: UpdateVersion?
            if let published = try await DirectUpdateAccess.shared.publishedVersion() {
                newest = UpdateVersion(published)
            } else {
                newest = try await newestGitHubVersion()
            }
            if let newest, newest > current {
                availableVersion = newest.components.map(String.init).joined(separator: ".")
                status = "Uma versão mais recente está disponível."
            } else {
                availableVersion = nil
                status = DirectUpdateAccess.shared.ready
                    ? "Nenhuma versão mais recente publicada."
                    : "Atualizações diretas ainda não estão ativadas neste iPhone. Abra seu link pessoal de instalação para ativá-las."
            }
        } catch {
            status = "Não foi possível verificar atualizações agora."
        }
    }

    private func newestGitHubVersion() async throws -> UpdateVersion? {
        var request = URLRequest(url: Self.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_000_000 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([UpdateRelease].self, from: data).compactMap(\.version).max()
    }
}
