import CoreLocation
import ImageIO
import SwiftUI
import Vision

struct GalleryControlSurface: ViewModifier {
    var tint: Color = .primary
    var interactive = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 15)
        if #available(iOS 26, *) {
            content.foregroundStyle(tint)
                .glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content.foregroundStyle(tint).background(.regularMaterial, in: shape)
        }
    }
}

struct GalleryFileInformation {
    let size: String?
    let dimensions: String?
    let location: CLLocation?
    let originalDate: String?

    init(url: URL) {
        size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        if let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
           let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            dimensions = "\(width) × \(height)"
        } else { dimensions = nil }
        originalDate = ExistingPhotoStamp.exifDateText(properties: properties)
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
           let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
           let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
           let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String,
           ["N", "S"].contains(latitudeRef), ["E", "W"].contains(longitudeRef),
           lat >= 0, lat <= 90, lon >= 0, lon <= 180 {
            location = CLLocation(latitude: latitudeRef == "S" ? -lat : lat,
                                  longitude: longitudeRef == "W" ? -lon : lon)
        } else { location = nil }
    }
}

enum GalleryPhotoActions {
    private static let stampQueue = DispatchQueue(label: "br.com.momentra.gallery-stamp", qos: .utility)

    static func recognizeText(in url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func copyWithStamp(url: URL, date: Date, profile: StampProfile) async throws -> URL {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 100 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let info = GalleryFileInformation(url: url)
        let layout = profile.layout
        let location = info.location.map {
            CLLocation(coordinate: $0.coordinate, altitude: 0, horizontalAccuracy: 0, verticalAccuracy: -1, timestamp: date)
        }
        let snapshot = StampSnapshot(capturedAt: date, gpsEnabled: location != nil, mapEnabled: layout.showsMap,
            addressEnabled: layout.showsAddress, note: profile.note, logo: ProfileLogoStore.load(profile.logoName),
            compact: layout.compact, position: layout.position, horizontal: layout.horizontal,
            longDate: layout.dateFormat == "long", fontStyle: layout.fontStyle,
            mapScale: layout.mapScale, mapCorner: layout.mapCorner, location: location, heading: nil, layout: layout)
        let metadata: (UIImage?, String?) = await withCheckedContinuation { continuation in
            stampQueue.async {
                StampMap.load(snapshot: snapshot, queue: stampQueue) { map in
                    StampAddress.load(snapshot: snapshot, queue: stampQueue) { address in
                        continuation.resume(returning: (map, address))
                    }
                }
            }
        }
        guard let rendered = StampRenderer.render(data, aspect: nil, snapshot: snapshot,
                                                   map: metadata.0, address: metadata.1) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let id = UUID()
        let stored = try ProcessedFileStore.save(rendered, captureID: id)
        try? PhotoProfileIndex.register(captureID: id, profile: CaptureProfileTag(id: profile.id, name: profile.name), captureDate: date)
        return stored
    }
}
