import SwiftUI
import MapKit
import CoreLocation

struct ProfileArea: Codable, Equatable, Identifiable {
    var id = UUID()
    var profileID: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var enabled = true

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) &&
        (-180...180).contains(longitude) && radius.isFinite && (50...5000).contains(radius)
    }
}

/// Local device preferences only: organization stamps remain read-only.
@MainActor
final class ProfileLocationRules: ObservableObject {
    static let shared = ProfileLocationRules()
    private let defaults: UserDefaults
    private let key = "native.profile.locationAreas.v1"
    private let fallbackKey = "native.profile.locationFallback.v1"
    private let autoKey = "native.profile.locationActive.v1"
    private let previousKey = "native.profile.locationPrevious.v1"
    @Published private(set) var areas: [ProfileArea]
    @Published private(set) var fallbackID: UUID?
    private var activeID: UUID?
    private var previousID: UUID?
    private var manualOverride = false
    private var outsideApplied = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        areas = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([ProfileArea].self, from: $0) } ?? []
        fallbackID = defaults.string(forKey: fallbackKey).flatMap(UUID.init(uuidString:))
        activeID = defaults.string(forKey: autoKey).flatMap(UUID.init(uuidString:))
        previousID = defaults.string(forKey: previousKey).flatMap(UUID.init(uuidString:))
    }
    var hasEnabledAreas: Bool { areas.contains { $0.enabled && $0.isValid } }
    func hasEnabledAreas(for ids: Set<UUID>) -> Bool {
        areas.contains { $0.enabled && $0.isValid && ids.contains($0.profileID) }
    }
    func areas(for profileID: UUID) -> [ProfileArea] { areas.filter { $0.profileID == profileID } }
    func save(_ profileID: UUID, areas edited: [ProfileArea], fallback: UUID?) {
        let valid = edited.filter { $0.profileID == profileID && $0.isValid }
        areas.removeAll { $0.profileID == profileID }
        areas.append(contentsOf: valid)
        if let data = try? JSONEncoder().encode(areas) { defaults.set(data, forKey: key) }
        fallbackID = fallback
        defaults.set(fallback?.uuidString, forKey: fallbackKey)
    }
    func manualSelection() {
        if activeID != nil { manualOverride = true; clearActive() }
    }
    private func clearActive() {
        activeID = nil; previousID = nil
        defaults.removeObject(forKey: autoKey); defaults.removeObject(forKey: previousKey)
    }
    func selection(for fix: CLLocation?, available: Set<UUID>, current: UUID) -> UUID? {
        guard let fix, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 100,
              abs(fix.timestamp.timeIntervalSinceNow) <= 30 else { return nil }
        let eligible = areas.filter { $0.enabled && $0.isValid && available.contains($0.profileID) }
        guard !eligible.isEmpty else { return nil }
        let measured = eligible.map { area in
            (area, fix.distance(from: CLLocation(latitude: area.latitude, longitude: area.longitude)))
        }
        let inside = measured.filter { $0.1 + fix.horizontalAccuracy <= $0.0.radius }
            .sorted { a, b in a.1 == b.1 ? a.0.id.uuidString < b.0.id.uuidString : a.1 < b.1 }
        if let chosen = inside.first?.0.profileID {
            outsideApplied = false
            guard !manualOverride else { return nil }
            if activeID == nil {
                previousID = current
                defaults.set(current.uuidString, forKey: previousKey)
            }
            activeID = chosen; defaults.set(chosen.uuidString, forKey: autoKey)
            return chosen == current ? nil : chosen
        }
        // Uncertainty touching any boundary must not trigger a profile change.
        guard measured.allSatisfy({ $0.1 - fix.horizontalAccuracy > $0.0.radius }) else { return nil }
        if manualOverride { manualOverride = false; outsideApplied = true; return nil }
        guard activeID != nil || !outsideApplied else { return nil }
        outsideApplied = true
        let target = fallbackID.flatMap { available.contains($0) ? $0 : nil }
            ?? previousID.flatMap { available.contains($0) ? $0 : nil }
        clearActive()
        return target == current ? nil : target
    }
}

struct ProfileLocationSettingsView: View {
    let profile: StampProfile
    let profiles: [StampProfile]
    let currentLocation: CLLocation?
    @ObservedObject var rules: ProfileLocationRules
    @Environment(\.dismiss) private var dismiss
    @State private var areas: [ProfileArea]
    @State private var fallback: UUID?
    @State private var editing: ProfileArea?

    init(profile: StampProfile, profiles: [StampProfile], currentLocation: CLLocation?, rules: ProfileLocationRules = .shared) {
        self.profile = profile; self.profiles = profiles; self.currentLocation = currentLocation; self.rules = rules
        _areas = State(initialValue: rules.areas(for: profile.id))
        _fallback = State(initialValue: rules.fallbackID)
    }
    var body: some View {
        Form {
            Section("Locais de \(profile.name)") {
                ForEach(areas) { area in
                    Button { FotomarcoHaptics.play(.buttons); editing = area } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.yellow)
                            VStack(alignment: .leading) {
                                Text(area.name.isEmpty ? "Local" : area.name).foregroundStyle(.primary)
                                Text("Raio de \(Int(area.radius)) m\(area.enabled ? "" : " · Desativado")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.onDelete { areas.remove(atOffsets: $0) }
                Button { FotomarcoHaptics.play(.buttons); let fix = currentLocation?.coordinate
                    editing = ProfileArea(profileID: profile.id, name: "Novo local", latitude: fix?.latitude ?? -14.235, longitude: fix?.longitude ?? -51.925, radius: 200)
                } label: { Label("Adicionar local", systemImage: "plus.circle.fill") }
            }
            Section {
                Picker("Fora das áreas", selection: $fallback) {
                    Text("Perfil anterior").tag(Optional<UUID>.none)
                    ForEach(profiles) { item in Text(item.name.isEmpty ? "Sem nome" : item.name).tag(Optional(item.id)) }
                }
            } footer: { Text("Esta escolha vale para todos os perfis. Ao sair de todas as áreas, o perfil escolhido será aplicado. As áreas são verificadas enquanto o Photomark está aberto e precisam de permissão de localização. A localização pode demorar a atualizar.") }
        }
        .navigationTitle("Ativação por localização").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Salvar") { rules.save(profile.id, areas: areas, fallback: fallback); dismiss() } }
        }
        .sheet(item: $editing) { area in
            NavigationStack {
                ProfileAreaEditor(area: area, locationKnown: currentLocation != nil || areas.contains(where: { $0.id == area.id })) { result in
                    if let index = areas.firstIndex(where: { $0.id == result.id }) { areas[index] = result }
                    else { areas.append(result) }
                }
            }
        }
    }
}

private struct ProfileAreaEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var area: ProfileArea
    @State private var position: MapCameraPosition
    @State private var locationKnown: Bool
    let save: (ProfileArea) -> Void
    init(area: ProfileArea, locationKnown: Bool, save: @escaping (ProfileArea) -> Void) {
        _area = State(initialValue: area)
        _locationKnown = State(initialValue: locationKnown)
        let distance = locationKnown ? max(1000, area.radius * 4) : 5_000_000
        _position = State(initialValue: .region(MKCoordinateRegion(center: area.coordinate, latitudinalMeters: distance, longitudinalMeters: distance)))
        self.save = save
    }
    var body: some View {
        VStack(spacing: 12) {
            Text("Arraste o mapa para posicionar o centro da área.").font(.footnote).foregroundStyle(.secondary)
            Map(position: $position) {
                MapCircle(center: area.coordinate, radius: area.radius).foregroundStyle(.yellow.opacity(0.20))
                Marker("Centro", coordinate: area.coordinate).tint(.yellow)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                area.latitude = context.region.center.latitude; area.longitude = context.region.center.longitude
                if context.region.span.latitudeDelta < 0.25 { locationKnown = true }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay { Image(systemName: "plus").foregroundStyle(.yellow).allowsHitTesting(false) }
            TextField("Nome do local", text: $area.name).textFieldStyle(.roundedBorder)
            HStack { Text("Raio"); Slider(value: $area.radius, in: 50...5000, step: 50).tint(.yellow); Text("\(Int(area.radius)) m").monospacedDigit().frame(width: 70, alignment: .trailing) }
            Toggle("Ativar neste local", isOn: $area.enabled)
        }.padding().navigationTitle("Local e raio").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Salvar") { if area.isValid && locationKnown { save(area); dismiss() } }.disabled(!area.isValid || !locationKnown) }
        }
    }
}
