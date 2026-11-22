import Foundation
import CoreLocation
import SwiftUI

struct GalleryMapRecord: Codable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
}

@MainActor final class GalleryMapStore: ObservableObject {
    @Published private(set) var index = GalleryMapIndex.build([])
    @Published private(set) var loading = false
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("FotomarcoMapIndex-v2.json")
    private var generation = UUID()
    private var restored = false

    func prepare(items: [GalleryItem]) async {
        let current = UUID(); generation = current
        if !restored {
            restored = true
            let location = file
            let cached = await Task.detached(priority: .utility) { () -> GalleryMapIndex? in
                guard let location, let data = try? Data(contentsOf: location) else { return nil }
                return try? JSONDecoder().decode(GalleryMapIndex.self, from: data)
            }.value
            guard generation == current, !Task.isCancelled else { restored = false; return }
            if let cached, cached.levels.count == 21 {
                index = cached
            }
        }
        guard !items.isEmpty else { return }
        loading = true
        defer { if generation == current { loading = false } }
        let old = Dictionary(index.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let legacy = (UserDefaults.standard.data(forKey: "native.gallery.captureMapCoordinates.v1"))
            .flatMap { try? JSONDecoder().decode([String: GalleryMapCoordinate].self, from: $0) } ?? [:]
        var seen = Set<String>()
        let photos = items.reversed().filter { item in
            !item.isVideo && seen.insert(item.captureIDForUpload?.uuidString ?? item.id).inserted
        }
        let lookup = await Task.detached(priority: .utility) { PhotoProfileIndex.load() }.value
        var records: [GalleryMapRecord] = []
        for item in photos {
            guard !Task.isCancelled, generation == current else { return }
            let key = item.captureIDForUpload?.uuidString ?? item.id
            if let saved = old[key] { records.append(saved); continue }
            if let saved = legacy[item.id] {
                records.append(.init(id: key, latitude: saved.latitude, longitude: saved.longitude)); continue
            }
            let sources = [item.source] + item.copies
            var point = item.captureIDForUpload.flatMap { lookup.locations[$0] }
            if point == nil {
                point = sources.compactMap { source -> CLLocationCoordinate2D? in
                    if case .device(let asset) = source { return asset.location?.coordinate }
                    return nil
                }.first
            }
            if point == nil, let url = sources.compactMap({ source -> URL? in
                if case .capture(let file) = source { return file.url }; return nil
            }).first {
                point = await Task.detached(priority: .utility) { GalleryFileInformation(url: url).location?.coordinate }.value
            }
            if let point, CLLocationCoordinate2DIsValid(point) {
                records.append(.init(id: key, latitude: point.latitude, longitude: point.longitude))
            }
        }
        guard !Task.isCancelled, generation == current else { return }
        let sorted = records.sorted { $0.id < $1.id }
        guard sorted != index.records else { return }
        let next = await Task.detached(priority: .utility) { GalleryMapIndex.build(sorted) }.value
        guard !Task.isCancelled, generation == current else { return }
        index = next
        if let file {
            _ = await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(next) else { return false }
                return (try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
            }.value
        }
    }
}

struct GalleryMapGroup: Codable, Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let itemIDs: [String]
}

struct GalleryMapIndex: Codable {
    let records: [GalleryMapRecord]
    let levels: [[GalleryMapGroup]]

    static func zoom(for span: Double) -> Int {
        guard span.isFinite, span > 0 else { return 0 }
        return max(0, min(20, Int(floor(log2(360 / span)))))
    }

    static func build(_ input: [GalleryMapRecord]) -> GalleryMapIndex {
        let records = input.filter {
            CLLocationCoordinate2DIsValid(.init(latitude: $0.latitude, longitude: $0.longitude))
        }.sorted { $0.id < $1.id }
        let levels = (0...20).map { zoom -> [GalleryMapGroup] in
            let divisions = pow(2.0, Double(zoom))
            let groups = Dictionary(grouping: records) { record in
                let x = Int(floor((record.longitude + 180) / 360 * divisions))
                let y = Int(floor((record.latitude + 90) / 180 * divisions))
                return "\(zoom):\(x):\(y)"
            }
            return groups.map { key, values in
                let count = Double(values.count)
                return GalleryMapGroup(id: key, latitude: values.reduce(0) { $0 + $1.latitude } / count,
                    longitude: values.reduce(0) { $0 + $1.longitude } / count, itemIDs: values.map(\.id))
            }.sorted { $0.id < $1.id }
        }
        return GalleryMapIndex(records: records, levels: levels)
    }
}
