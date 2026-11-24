import Foundation
import Combine

struct StampProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var note: String = ""
    var logoName: String = ""
    var layout: StampLayout = StampLayout()
    var effectiveLogoName: String {
        guard layout.template != .original else { return logoName }
        return layout.templateValues[layout.template.rawValue]?["_image"] ?? ""
    }
    var additionalLogoNames: [String] {
        guard layout.template == .construction else { return [] }
        let fields = layout.templateValues[layout.template.rawValue] ?? [:]
        return [fields["_image2"] ?? "", fields["_image3"] ?? ""]
    }
}

/// Legacy keys remain intact for recovery and for older app versions.
@MainActor
final class StampProfilesStore: ObservableObject {
    // The personal default must not displace any of the five existing profiles.
    static let maximumProfiles = 6
    private let defaults: UserDefaults
    private let isDraft: Bool
    private let profilesKey = "native.stamp.layoutProfiles.v1"
    private let selectedKey = "native.stamp.selectedLayoutProfile.v1"
    private let startupKey = "native.stamp.startupProfile.v1"

    @Published private(set) var profiles: [StampProfile] { didSet { persist() } }
    /// Organization profiles are separately held immutable snapshots, never personal drafts.
    @Published private(set) var organizationProfiles: [StampProfile] = []
    @Published private(set) var selectedID: UUID {
        didSet { if !isDraft && profiles.contains(where: { $0.id == selectedID }) { defaults.set(selectedID.uuidString, forKey: selectedKey) } }
    }
    /// "last" or a profile UUID; only applied on a new app launch.
    @Published private(set) var startupSelection: String {
        didSet { if !isDraft { defaults.set(startupSelection, forKey: startupKey) } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isDraft = false
        let profileKey = "native.stamp.layoutProfiles.v1"
        let selectionKey = "native.stamp.selectedLayoutProfile.v1"
        let startupKey = "native.stamp.startupProfile.v1"
        let migrationKey = "native.stamp.profileSettingsMigrated.v1"
        let personalDefaultKey = "native.stamp.personalDefaultCreated.v1"
        let data = defaults.data(forKey: profileKey)
        var loaded: [StampProfile]
        if let data, let saved = try? JSONDecoder().decode([StampProfile].self, from: data),
           !saved.isEmpty, saved.count <= Self.maximumProfiles, Set(saved.map(\.id)).count == saved.count {
            loaded = saved
        } else {
            let previous = defaults.string(forKey: "native.profile") ?? "HAMOA"
            let key = previous == "PIRESCO" ? "piresco" : previous == "PESSOAL" ? "pessoal" : "hamoa"
            loaded = [StampProfile(name: "Padrão",
                note: defaults.string(forKey: "native.profile.\(key).note") ?? "",
                logoName: defaults.string(forKey: "native.profile.\(key).logo") ?? "")]
            if let data, defaults.data(forKey: profileKey + ".recovery") == nil {
                defaults.set(data, forKey: profileKey + ".recovery")
            }
        }
        let hasLegacyData = data != nil || defaults.object(forKey: "native.profile") != nil
        let previousFirstID = loaded[0].id
        if !defaults.bool(forKey: personalDefaultKey) {
            if let index = loaded.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Pessoal") == .orderedSame }) {
                let existing = loaded.remove(at: index)
                loaded.insert(existing, at: 0)
            } else {
                var layout = StampLayout()
                layout.mode = .separate
                layout.showsLogo = false
                layout.showsMap = true
                layout.showsInformation = true
                layout.map = StampPoint(x: 0.15, y: 0.88)
                let personal = StampProfile(name: "Pessoal", layout: layout)
                if hasLegacyData { loaded.insert(personal, at: 0) } else { loaded = [personal] }
            }
        }
        let last = defaults.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
        let lastID = loaded.first(where: { $0.id == last })?.id ?? (hasLegacyData ? previousFirstID : loaded[0].id)
        if !defaults.bool(forKey: migrationKey), let index = loaded.firstIndex(where: { $0.id == lastID }) {
            Self.importLegacyAppearance(into: &loaded[index].layout, defaults: defaults)
            defaults.set(true, forKey: migrationKey)
        }
        let savedStartup = defaults.string(forKey: startupKey) ?? "last"
        let fixed = UUID(uuidString: savedStartup).flatMap { id in loaded.first(where: { $0.id == id })?.id }
        self.profiles = loaded
        self.startupSelection = fixed?.uuidString ?? "last"
        self.selectedID = fixed ?? lastID
        defaults.set(try? JSONEncoder().encode(loaded), forKey: profileKey)
        defaults.set(true, forKey: personalDefaultKey)
        defaults.set(self.selectedID.uuidString, forKey: selectionKey)
        defaults.set(self.startupSelection, forKey: startupKey)
    }

    init(draftOf source: StampProfilesStore) {
        defaults = source.defaults
        isDraft = true
        profiles = source.profiles
        let previous = source.defaults.string(forKey: "native.stamp.selectedLayoutProfile.v1").flatMap(UUID.init(uuidString:))
        selectedID = source.profiles.contains(where: { $0.id == source.selectedID }) ? source.selectedID :
            (source.profiles.first(where: { $0.id == previous })?.id ?? source.profiles[0].id)
        startupSelection = source.startupSelection
    }

    func applyDraft(_ draft: StampProfilesStore) {
        let keepOrganizationSelection = isOrganizationSelected
        profiles = draft.profiles
        if !keepOrganizationSelection { selectedID = draft.selectedID }
        startupSelection = draft.startupSelection
    }

    var availableProfiles: [StampProfile] { profiles + organizationProfiles }
    var isOrganizationSelected: Bool { organizationProfiles.contains(where: { $0.id == selectedID }) }
    var selected: StampProfile { availableProfiles.first(where: { $0.id == selectedID }) ?? profiles[0] }

    /// The organization ID is the stable ID of its read-only profile. Personal
    /// IDs are never replaced and snapshots are never written into personal keys.
    func replaceOrganizationProfiles(_ snapshots: [(organizationID: String, profile: StampProfile)]) {
        var ids = Set(profiles.map(\.id))
        var result: [StampProfile] = []
        for snapshot in snapshots {
            guard let id = UUID(uuidString: snapshot.organizationID), ids.insert(id).inserted else { continue }
            var profile = snapshot.profile
            profile.id = id
            result.append(profile)
        }
        let wasOrganization = isOrganizationSelected
        organizationProfiles = result
        if wasOrganization && !result.contains(where: { $0.id == selectedID }) {
            let previous = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
            selectedID = profiles.first(where: { $0.id == previous })?.id ?? profiles[0].id
        }
    }

    func select(_ id: UUID) {
        guard availableProfiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func setStartup(_ value: String) {
        if value == "last" { startupSelection = value; return }
        guard let id = UUID(uuidString: value), profiles.contains(where: { $0.id == id }) else { return }
        startupSelection = id.uuidString
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
        let removed = selectedID
        profiles.remove(at: index)
        selectedID = profiles[min(index, profiles.count - 1)].id
        if startupSelection == removed.uuidString || profiles.count == 1 { startupSelection = "last" }
    }

    func rename(_ value: String) { update { $0.name = String(value.prefix(60)) } }
    func setNote(_ value: String) { update { $0.note = String(value.prefix(96)) } }
    func setLayout(_ value: StampLayout) { update { $0.layout = value } }

    func setLogo(_ value: String, for id: UUID, template: StampLayout.Template = .original, slot: Int = 0) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        guard (0...2).contains(slot), slot == 0 || template == .construction else { return }
        if template == .original { profiles[index].logoName = value }
        else {
            let key = slot == 0 ? "_image" : "_image\(slot + 1)"
            profiles[index].layout.templateValues[template.rawValue, default: [:]][key] = value
        }
    }

    private func update(_ change: (inout StampProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        change(&profiles[index])
    }
    private func persist() {
        guard !isDraft else { return }
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: profilesKey)
    }
    private static func importLegacyAppearance(into layout: inout StampLayout, defaults: UserDefaults) {
        layout.fontStyle = defaults.string(forKey: "native.stamp.font") ?? layout.fontStyle
        layout.dateFormat = defaults.string(forKey: "native.stamp.dateFormat") ?? layout.dateFormat
        layout.position = defaults.string(forKey: "native.stamp.position") ?? layout.position
        layout.horizontal = defaults.string(forKey: "native.stamp.horizontal") ?? layout.horizontal
        layout.mapScale = defaults.string(forKey: "native.map.scale") ?? layout.mapScale
        layout.mapCorner = defaults.string(forKey: "native.map.corner") ?? layout.mapCorner
        layout.logoCorner = defaults.string(forKey: "native.logo.corner") ?? layout.logoCorner
        layout.compact = defaults.string(forKey: "native.stamp.size") == "compact"
        if defaults.object(forKey: "native.map.enabled") != nil { layout.showsMap = defaults.bool(forKey: "native.map.enabled") }
        if defaults.object(forKey: "native.address.enabled") != nil { layout.showsAddress = defaults.bool(forKey: "native.address.enabled") }
    }
}
