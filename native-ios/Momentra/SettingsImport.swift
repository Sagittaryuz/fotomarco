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
