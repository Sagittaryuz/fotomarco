import SwiftUI
import MapKit
import Photos

private struct GalleryMapCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

private struct GalleryMapCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let items: [GalleryItem]
}

enum GalleryMapBinning {
    static func key(latitude: Double, longitude: Double, span: Double) -> String {
        let size = max(0.0001, min(90, span / 5))
        return "\(Int(floor((latitude + 90) / size))):\(Int(floor((longitude + 180) / size)))"
    }
}

/// The source is the Fotomarco capture projection; unrelated Photos assets are never fetched.
struct GalleryCaptureMap: View {
    let items: [GalleryItem]
    let open: (GalleryItem) -> Void
    @State private var position: MapCameraPosition = .automatic
    @State private var longitudeSpan = 180.0
    @State private var satellite = false
    @State private var coordinates: [String: GalleryMapCoordinate] = [:]
    @State private var attempted = Set<String>()
    @State private var selectedCluster: GalleryMapCluster?
    @State private var pendingItem: GalleryItem?
    @State private var loading = false
    @Namespace private var mapScope
    private let cacheKey = "native.gallery.captureMapCoordinates.v1"

    private var photos: [GalleryItem] {
        var seen = Set<String>()
        return items.reversed().filter { item in
            guard !item.isVideo else { return false }
            let key = item.captureIDForUpload?.uuidString ?? item.id
            return seen.insert(key).inserted
        }
    }

    private var clusters: [GalleryMapCluster] {
        let located = photos.compactMap { item -> (GalleryItem, GalleryMapCoordinate)? in
            coordinates[item.id].map { (item, $0) }
        }
        let groups = Dictionary(grouping: located) { pair in
            GalleryMapBinning.key(latitude: pair.1.latitude, longitude: pair.1.longitude, span: longitudeSpan)
        }
        return groups.map { key, group in
            let count = Double(group.count)
            return GalleryMapCluster(id: key,
                coordinate: .init(latitude: group.reduce(0) { $0 + $1.1.latitude } / count,
                                  longitude: group.reduce(0) { $0 + $1.1.longitude } / count),
                items: group.map(\.0))
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                ForEach(clusters) { cluster in
                    Annotation("\(cluster.items.count) fotos", coordinate: cluster.coordinate, anchor: .bottom) {
                        Button { FotomarcoHaptics.play(.gallery); selectedCluster = cluster } label: {
                            mapMarker(cluster)
                        }.buttonStyle(.plain)
                    }
                }
                UserAnnotation()
            }
            .mapStyle(satellite ? .imagery : .standard)
            .mapScope(mapScope)
            .onMapCameraChange(frequency: .onEnd) { context in longitudeSpan = context.region.span.longitudeDelta }
            .accessibilityLabel("Mapa das capturas do Fotomarco")
            VStack(spacing: 6) {
                Button {
                    FotomarcoHaptics.play(.gallery)
                    satellite.toggle()
                } label: {
                    Image(systemName: satellite ? "map.fill" : "globe.americas.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(satellite ? "Mostrar mapa" : "Mostrar satélite")
                MapUserLocationButton(scope: mapScope)
                    .frame(width: 44, height: 44)
            }
            .modifier(GalleryControlSurface(rounded: true))
            .padding(12)
            if loading {
                ProgressView("Localizando fotos…")
                    .font(.caption).padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            } else if !photos.isEmpty && !photos.contains(where: { coordinates[$0.id] != nil }) {
                Text("Nenhuma captura com localização disponível.")
                    .font(.footnote).padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .task(id: photos.map(\.id)) { await loadLocations() }
        .sheet(item: $selectedCluster, onDismiss: {
            if let pendingItem { self.pendingItem = nil; open(pendingItem) }
        }) { cluster in
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                        ForEach(cluster.items) { item in
                            Button {
                                FotomarcoHaptics.play(.gallery)
                                pendingItem = item
                                selectedCluster = nil
                            } label: {
                                item.thumbnail().aspectRatio(1, contentMode: .fill).clipped()
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .background(.black)
                .navigationTitle("\(cluster.items.count) fotos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Concluído") { selectedCluster = nil } } }
            }.preferredColorScheme(.dark)
        }
    }

    private func mapMarker(_ cluster: GalleryMapCluster) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let item = cluster.items.first { item.thumbnail().frame(width: 72, height: 72).clipped() }
                if cluster.items.count > 1 {
                    Text(cluster.items.count.formatted()).font(.caption.bold()).foregroundStyle(.white)
                        .padding(4).background(.black.opacity(0.55), in: Capsule()).padding(3)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 3))
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 16)).foregroundStyle(.white).offset(y: -3)
        }
        .accessibilityLabel(cluster.items.count == 1 ? "Uma foto neste local" : "\(cluster.items.count) fotos neste local")
    }

    @MainActor private func loadLocations() async {
        if coordinates.isEmpty, let data = UserDefaults.standard.data(forKey: cacheKey),
           let saved = try? JSONDecoder().decode([String: GalleryMapCoordinate].self, from: data) { coordinates = saved }
        loading = true
        defer {
            loading = false
            if let data = try? JSONEncoder().encode(coordinates) { UserDefaults.standard.set(data, forKey: cacheKey) }
        }
        for item in photos where coordinates[item.id] == nil && !attempted.contains(item.id) {
            guard !Task.isCancelled else { return }
            attempted.insert(item.id)
            let sources = [item.source] + item.copies
            let localLocation = sources.compactMap { source -> CLLocation? in
                if case .device(let asset) = source { return asset.location }
                return nil
            }.first
            let localURL = sources.compactMap { source -> URL? in
                if case .capture(let capture) = source { return capture.url }
                return nil
            }.first
            var location = localLocation
            if location == nil, let localURL {
                location = await Task.detached(priority: .utility) { GalleryFileInformation(url: localURL).location }.value
            }
            if location == nil, localURL == nil, let input = try? await item.input() {
                let url = input.url
                location = await Task.detached(priority: .utility) { GalleryFileInformation(url: url).location }.value
                input.close()
            }
            if Task.isCancelled { attempted.remove(item.id); return }
            if let coordinate = location?.coordinate, CLLocationCoordinate2DIsValid(coordinate) {
                coordinates[item.id] = .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
    }
}
