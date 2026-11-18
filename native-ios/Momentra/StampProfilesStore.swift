import Foundation
import Combine

struct StampProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var note: String = ""
    var logoName: String = ""
    var layout: StampLayout = StampLayout()
}

/// The old keys remain intact for recovery and for older versions of the app.
@MainActor
final class StampProfilesStore: ObservableObject {
    static let maximumProfiles = 5
    private let defaults: UserDefaults
    private let profilesKey = "native.stamp.layoutProfiles.v1"
    private let selectedKey = "native.stamp.selectedLayoutProfile.v1"

    @Published private(set) var profiles: [StampProfile] {
        didSet { persist() }
    }
    @Published private(set) var selectedID: UUID {
        didSet { defaults.set(selectedID.uuidString, forKey: selectedKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: profilesKey),
           let saved = try? JSONDecoder().decode([StampProfile].self, from: data),
           !saved.isEmpty, saved.count <= Self.maximumProfiles,
           Set(saved.map(\.id)).count == saved.count {
            profiles = saved
            let candidate = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
            selectedID = saved.contains(where: { $0.id == candidate }) ? candidate! : saved[0].id
        } else {
            let previous = defaults.string(forKey: "native.profile") ?? "HAMOA"
            let key = previous == "PIRESCO" ? "piresco" : previous == "PESSOAL" ? "pessoal" : "hamoa"
            let initial = StampProfile(name: "Padrão",
                note: defaults.string(forKey: "native.profile.\(key).note") ?? "",
                logoName: defaults.string(forKey: "native.profile.\(key).logo") ?? "")
            profiles = [initial]
            selectedID = initial.id
            // Preserve an unreadable archive separately before creating a usable default.
            if let oldData = defaults.data(forKey: profilesKey),
               defaults.data(forKey: profilesKey + ".recovery") == nil {
                defaults.set(oldData, forKey: profilesKey + ".recovery")
            }
            defaults.set(try? JSONEncoder().encode(profiles), forKey: profilesKey)
            defaults.set(selectedID.uuidString, forKey: selectedKey)
        }
    }

    var selected: StampProfile {
        profiles.first(where: { $0.id == selectedID }) ?? profiles[0]
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    @discardableResult
    func create() -> Bool {
        guard profiles.count < Self.maximumProfiles else { return false }
        let newProfile = StampProfile(name: "Novo perfil")
        profiles.append(newProfile)
        selectedID = newProfile.id
        return true
    }

    func removeSelected() {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        profiles.remove(at: index)
        selectedID = profiles[min(index, profiles.count - 1)].id
    }

    func rename(_ value: String) { update { $0.name = String(value.prefix(60)) } }
    func setNote(_ value: String) { update { $0.note = String(value.prefix(96)) } }
    func setLayout(_ value: StampLayout) { update { $0.layout = value } }

    func setLogo(_ value: String, for id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].logoName = value
    }

    private func update(_ change: (inout StampProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        change(&profiles[index])
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: profilesKey)
    }
}
