import Foundation

struct SettingsTransfer: Decodable {
    struct Profile: Decodable {
        let title: String
        let note: String
        let hasLogo: Bool
    }
    struct Settings: Decodable {
        let profile: String
        let stamp: Bool
        let gps: Bool
        let map: Bool
        let aspectRatio: String
        let storageMode: String
        let allowGallery: Bool
        let size: String?
        let position: String?
        let timestampFormat: String?
        let timestampFont: String?
        let mapScale: String?
        let profiles: [String: Profile]
    }
    let format: String
    let version: Int
    let settings: Settings

    static func decode(_ data: Data) throws -> SettingsTransfer {
        guard data.count <= 65_536 else { throw ImportError.invalid }
        let transfer = try JSONDecoder().decode(Self.self, from: data)
        let s = transfer.settings
        let ids = ["HAMOA", "PIRESCO", "PESSOAL"]
        guard transfer.format == "momentra-settings", transfer.version == 1,
              ids.contains(s.profile), PhotoAspect(rawValue: s.aspectRatio) != nil,
              s.size.map({ ["compact", "regular"].contains($0) }) ?? true,
              s.position.map({ ["top", "bottom"].contains($0) }) ?? true,
              s.timestampFormat.map({ ["numeric", "long"].contains($0) }) ?? true,
              s.timestampFont.map({ ["system", "serif", "mono"].contains($0) }) ?? true,
              s.mapScale.map({ ["small", "medium", "large"].contains($0) }) ?? true,
              ids.allSatisfy({ s.profiles[$0] != nil }),
              s.profiles.values.allSatisfy({ $0.title.count <= 1000 && $0.note.count <= 1000 }) else { throw ImportError.invalid }
        // Cloud-only storage must not silently change to local storage.
        guard s.storageMode == "local" else { throw ImportError.unsupportedStorage }
        return transfer
    }

    enum ImportError: LocalizedError {
        case invalid, unsupportedStorage
        var errorDescription: String? {
            switch self {
            case .invalid: return "Arquivo de ajustes inválido ou incompatível. Nenhuma configuração foi alterada."
            case .unsupportedStorage: return "Os ajustes usam armazenamento ainda não disponível no app nativo. Nenhuma configuração foi alterada."
            }
        }
    }
}
