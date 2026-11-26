import SwiftUI
import MapKit
import Photos

struct GalleryMapCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct GalleryMapMarker: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let item: GalleryItem

    static func project(_ photos: [GalleryItem], records: [GalleryMapRecord]) -> [Self] {
        let locations = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return photos.compactMap { item in
            let id = item.captureIDForUpload?.uuidString ?? item.id
            guard let location = locations[id] else { return nil }
            return Self(id: id, coordinate: .init(latitude: location.latitude, longitude: location.longitude), item: item)
        }
    }
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
    var bottomInset: CGFloat = 0
    @StateObject private var currentLocation = LocationService()
    @State private var position: MapCameraPosition = .automatic
    @State private var centeredOnCurrentLocation = false
    @State private var pendingRecenter = false
    @State private var mapHeading = 0.0
    @State private var satellite = true
    @Namespace private var mapScope

    private var photos: [GalleryItem] {
        var seen = Set<String>()
        return items.reversed().filter { item in
            guard !item.isVideo else { return false }
            let key = item.captureIDForUpload?.uuidString ?? item.id
            return seen.insert(key).inserted
        }
    }

    private var clusters: [GalleryMapMarker] {
        GalleryMapMarker.project(photos, records: store.index.records)
    }

    var body: some View {
        let markers = clusters
        return ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                ForEach(markers) { cluster in
                    Annotation("Foto", coordinate: cluster.coordinate, anchor: .bottom) {
                        Button { FotomarcoHaptics.play(.gallery); open(cluster.item) } label: {
                            mapMarker(cluster)
                        }.buttonStyle(.plain)
                    }
                }
                UserAnnotation()
            }
            .mapStyle(satellite ? .imagery : .standard)
            .mapScope(mapScope)
            .onMapCameraChange(frequency: .continuous) { context in
                if abs(mapHeading - context.camera.heading) >= 0.5 { mapHeading = context.camera.heading }
            }
            .accessibilityLabel("Mapa das capturas do Photomark")
            VStack(spacing: 4) {
                Button {
                    FotomarcoHaptics.play(.gallery)
                    satellite.toggle()
                } label: {
                    Image(systemName: satellite ? "map.fill" : "globe.americas.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(satellite ? "Mostrar mapa" : "Mostrar satélite")
                Button {
                    FotomarcoHaptics.play(.gallery)
                    if let location = currentLocation.location {
                        recenter(on: location)
                    } else {
                        pendingRecenter = true
                        currentLocation.setEnabled(true)
                    }
                } label: {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 21, weight: .medium))
                        .rotationEffect(.degrees(-mapHeading))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Centralizar na minha localização e orientar para o norte")
            }
            .padding(4)
            .modifier(GalleryControlSurface(rounded: true))
            .padding(12)
            if store.loading {
                ProgressView("Localizando fotos…")
                    .font(.caption).padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            } else if !photos.isEmpty && markers.isEmpty {
                Text("Nenhuma captura com localização disponível.")
                    .font(.footnote).padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            if markers.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(markers) { marker in
                            let item = marker.item
                            Button {
                                FotomarcoHaptics.play(.gallery)
                                open(item)
                            } label: {
                                item.mapThumbnail()
                                    .frame(width: 52, height: 52)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.85), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.date.map { "Abrir foto de \($0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(GalleryDateSelection.brazilianLocale)))" } ?? "Abrir foto")
                        }
                    }
                    .padding(8)
                }
                .modifier(GalleryControlSurface(rounded: true))
                .padding(.horizontal, 12)
                .padding(.bottom, max(8, bottomInset + 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityIdentifier("gallery.map.photos")
                .accessibilityLabel("Fotos no mapa")
            }
        }
        .onAppear {
            satellite = true
            centeredOnCurrentLocation = false
            pendingRecenter = false
            currentLocation.setEnabled(true)
        }
        .onDisappear { currentLocation.setEnabled(false) }
        .onChange(of: currentLocation.location?.timestamp) { _, _ in
            guard let location = currentLocation.location else { return }
            guard pendingRecenter || (!centeredOnCurrentLocation && !position.positionedByUser) else { return }
            recenter(on: location)
        }
    }

    private func recenter(on location: CLLocation) {
        centeredOnCurrentLocation = true
        pendingRecenter = false
        position = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 2000, heading: 0, pitch: 0))
    }

    private func mapMarker(_ cluster: GalleryMapMarker) -> some View {
        VStack(spacing: 0) {
            cluster.item.mapThumbnail().frame(width: 72, height: 72).clipped()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 3))
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 16)).foregroundStyle(.white).offset(y: -3)
        }
        .accessibilityLabel("Uma foto neste local")
    }

}
