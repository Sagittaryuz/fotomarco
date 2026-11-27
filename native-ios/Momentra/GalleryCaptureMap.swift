import SwiftUI
import MapKit
import Photos
#if DEBUG
import UIKit
#endif

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

private struct GalleryMapCoincidentPhotos: Identifiable {
    let id: String
    let markers: [GalleryMapMarker]
}

enum GalleryMapBinning {
    static func key(latitude: Double, longitude: Double, span: Double) -> String {
        let size = max(0.0001, min(90, span / 5))
        return "\(Int(floor((latitude + 90) / size))):\(Int(floor((longitude + 180) / size)))"
    }
}

enum GalleryMapFraming {
    /// Fit the shortest longitude arc, including captures on either side of the date line.
    static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let valid = coordinates.filter { CLLocationCoordinate2DIsValid($0) && $0.latitude.isFinite && $0.longitude.isFinite }
        guard let first = valid.first else { return nil }
        let minLat = valid.map(\.latitude).min() ?? first.latitude
        let maxLat = valid.map(\.latitude).max() ?? first.latitude
        let longitudes = valid.map { ($0.longitude + 360).truncatingRemainder(dividingBy: 360) }.sorted()
        var largestGap = -1.0
        var start = longitudes[0]
        for index in longitudes.indices {
            let next = index + 1 < longitudes.count ? longitudes[index + 1] : longitudes[0] + 360
            let gap = next - longitudes[index]
            if gap > largestGap { largestGap = gap; start = next.truncatingRemainder(dividingBy: 360) }
        }
        let longitudeWidth = max(0, 360 - largestGap)
        let longitudeCenter = (start + longitudeWidth / 2 + 180).truncatingRemainder(dividingBy: 360) - 180
        return MKCoordinateRegion(center: .init(latitude: (minLat + maxLat) / 2, longitude: longitudeCenter),
            span: .init(latitudeDelta: min(180, max(0.005, (maxLat - minLat) * 1.6)),
                        longitudeDelta: min(360, max(0.005, longitudeWidth * 1.6))))
    }
}

/// The source is the Fotomarco capture projection; unrelated Photos assets are never fetched.
struct GalleryCaptureMap: View {
    let items: [GalleryItem]
    let open: (GalleryItem) -> Void
    @ObservedObject var store: GalleryMapStore
    var bottomInset: CGFloat = 0
    var locatesUser = true
    @StateObject private var currentLocation = LocationService()
    @State private var position: MapCameraPosition = .automatic
    @State private var centeredOnCurrentLocation = false
    @State private var pendingRecenter = false
    @State private var mapHeading = 0.0
    @State private var satellite = true
    @State private var coincidentPhotos: GalleryMapCoincidentPhotos?
    @State private var pendingPhoto: GalleryItem?
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
                        Button {
                            FotomarcoHaptics.play(.gallery)
                            let sameLocation = markers.filter {
                                $0.coordinate.latitude == cluster.coordinate.latitude && $0.coordinate.longitude == cluster.coordinate.longitude
                            }
                            if sameLocation.count == 1 { open(cluster.item) }
                            else { coincidentPhotos = .init(id: cluster.id, markers: sameLocation) }
                        } label: {
                            mapMarker(cluster)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("gallery.map.marker.\(cluster.id)")
                    }.annotationTitles(.hidden)
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
        }
        .onAppear {
            satellite = true
            centeredOnCurrentLocation = false
            pendingRecenter = false
            fit(markers)
            if locatesUser { currentLocation.setEnabled(true) }
        }
        .onChange(of: items.map(\.id)) { _, _ in fit(clusters) }
        .onChange(of: markers.map { "\($0.id):\($0.coordinate.latitude):\($0.coordinate.longitude)" }) { _, _ in
            if !position.positionedByUser { fit(clusters) }
        }
        .onDisappear { currentLocation.setEnabled(false) }
        .sheet(item: $coincidentPhotos, onDismiss: {
            if let item = pendingPhoto { pendingPhoto = nil; open(item) }
        }) { group in
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(group.markers) { marker in
                            Button {
                                FotomarcoHaptics.play(.gallery)
                                pendingPhoto = marker.item
                                coincidentPhotos = nil
                            } label: {
                                marker.item.mapThumbnail().aspectRatio(1, contentMode: .fill)
                                    .frame(minWidth: 96, minHeight: 96).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("gallery.map.photo.\(marker.id)")
                            .accessibilityLabel("Abrir foto neste local")
                        }
                    }.padding()
                }
                .navigationTitle("Fotos neste local")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { coincidentPhotos = nil } } }
            }
        }
        .onChange(of: currentLocation.location?.timestamp) { _, _ in
            guard let location = currentLocation.location else { return }
            guard pendingRecenter || (clusters.isEmpty && !store.loading && !centeredOnCurrentLocation && !position.positionedByUser) else { return }
            recenter(on: location)
        }
    }

    private func fit(_ markers: [GalleryMapMarker]) {
        guard let region = GalleryMapFraming.region(for: markers.map(\.coordinate)) else { return }
        position = .region(region)
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

#if DEBUG
/// Synthetic fixture for exercising overlapping points without accessing user photos.
struct GalleryMapOverlapFixture: View {
    static let ids = (1...8).map { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", $0))! }
    private let items: [GalleryItem]
    @StateObject private var store: GalleryMapStore
    @State private var selected = ""

    init() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = Self.ids.map { GalleryMapRecord(id: $0.uuidString, latitude: -17.88, longitude: -51.71) }
        _store = StateObject(wrappedValue: GalleryMapStore(testRecords: records))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("photomark-map-test", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        items = Self.ids.enumerated().map { index, id in
            let url = directory.appendingPathComponent(id.uuidString + ".jpg")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
                UIColor(hue: CGFloat(index) / 8, saturation: 0.55, brightness: 0.8, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
            }
            try? image.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
            return GalleryItem(source: .capture(.init(url: url, isVideo: false, isProcessed: true, date: date)), date: date, profile: nil)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GalleryCaptureMap(items: items, open: { selected = $0.captureIDForUpload?.uuidString ?? "" },
                              store: store, bottomInset: 72, locatesUser: false)
            Text(selected.isEmpty ? "Mapa de teste" : "Selecionada \(selected)")
                .accessibilityIdentifier("gallery.map.test.selection")
                .padding().background(.black.opacity(0.8))
        }
        .preferredColorScheme(.dark)
    }
}
#endif
