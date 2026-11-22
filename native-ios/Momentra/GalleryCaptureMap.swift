import SwiftUI
import MapKit
import Photos

struct GalleryMapCoordinate: Codable {
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
    @ObservedObject var store: GalleryMapStore
    @State private var position: MapCameraPosition = .automatic
    @State private var longitudeSpan = 180.0
    @State private var satellite = false
    @State private var selectedCluster: GalleryMapCluster?
    @State private var pendingItem: GalleryItem?
    @Namespace private var mapScope

    private var photos: [GalleryItem] {
        var seen = Set<String>()
        return items.reversed().filter { item in
            guard !item.isVideo else { return false }
            let key = item.captureIDForUpload?.uuidString ?? item.id
            return seen.insert(key).inserted
        }
    }

    private var clusters: [GalleryMapCluster] {
        let byID = Dictionary(photos.map { ($0.captureIDForUpload?.uuidString ?? $0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let locations = Dictionary(store.index.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let zoom = GalleryMapIndex.zoom(for: longitudeSpan)
        guard store.index.levels.indices.contains(zoom) else { return [] }
        return store.index.levels[zoom].compactMap { group in
            let matched = group.itemIDs.compactMap { byID[$0] }
            guard !matched.isEmpty else { return nil }
            let points = matched.compactMap { locations[$0.captureIDForUpload?.uuidString ?? $0.id] }
            let count = Double(points.count)
            guard count > 0 else { return nil }
            return GalleryMapCluster(id: group.id, coordinate: .init(latitude: points.reduce(0) { $0 + $1.latitude } / count,
                longitude: points.reduce(0) { $0 + $1.longitude } / count), items: matched)
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
            .accessibilityLabel("Mapa das capturas do Photomark")
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
            if store.loading {
                ProgressView("Localizando fotos…")
                    .font(.caption).padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            } else if !photos.isEmpty && clusters.isEmpty {
                Text("Nenhuma captura com localização disponível.")
                    .font(.footnote).padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
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
                                item.mapThumbnail().aspectRatio(1, contentMode: .fill).clipped()
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
                if let item = cluster.items.first { item.mapThumbnail().frame(width: 72, height: 72).clipped() }
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

}
