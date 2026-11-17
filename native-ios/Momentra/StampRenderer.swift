import CoreLocation
import UIKit
import MapKit

struct StampSnapshot {
    let capturedAt: Date
    let gpsEnabled: Bool
    let mapEnabled: Bool
    let addressEnabled: Bool
    let location: CLLocation?
    let heading: CLHeading?

    init(capturedAt: Date, gpsEnabled: Bool, mapEnabled: Bool = false, addressEnabled: Bool = false, location: CLLocation?, heading: CLHeading?) {
        self.capturedAt = capturedAt
        self.gpsEnabled = gpsEnabled
        self.mapEnabled = gpsEnabled && mapEnabled
        self.addressEnabled = gpsEnabled && addressEnabled
        if gpsEnabled, let location, CLLocationCoordinate2DIsValid(location.coordinate),
           location.horizontalAccuracy >= 0, location.timestamp <= capturedAt,
           capturedAt.timeIntervalSince(location.timestamp) <= 60 {
            self.location = location
        } else { self.location = nil }
        if gpsEnabled, let heading, heading.headingAccuracy >= 0, heading.timestamp <= capturedAt,
           capturedAt.timeIntervalSince(heading.timestamp) <= 10 {
            self.heading = heading
        } else { self.heading = nil }
    }

    var lines: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss 'GMT'XXXXX"
        var result = [formatter.string(from: capturedAt)]
        if let location {
            result.insert(String(format: "Lat: %.6f  Lon: %.6f", location.coordinate.latitude, location.coordinate.longitude), at: 0)
            result.append(String(format: "Precisão: ±%.0f m", location.horizontalAccuracy))
            if location.verticalAccuracy >= 0 { result.append(String(format: "Altitude: %.1f m", location.altitude)) }
        } else {
            result.insert(gpsEnabled ? "Localização indisponível" : "Localização desativada", at: 0)
        }
        if let heading {
            let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            if degrees >= 0 { result.append(String(format: "Direção: %.0f°", degrees)) }
        }
        return result
    }
}

enum StampRenderer {
    static func render(_ data: Data, snapshot: StampSnapshot, map: UIImage? = nil, address: String? = nil) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let result = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
            let unit = min(size.width, size.height)
            let margin = unit * 0.035
            let font = UIFont.systemFont(ofSize: max(12, unit * 0.027), weight: .medium)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph]
            let lines = (address.map { [$0] } ?? []) + snapshot.lines
            let text = lines.joined(separator: "\n") as NSString
            let mapSide = map == nil ? 0 : unit * 0.20
            let mapGap = map == nil ? 0 : margin
            let textWidth = size.width - margin * 4 - mapSide - mapGap
            let measured = text.boundingRect(with: CGSize(width: textWidth, height: size.height * 0.6), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            let height = max(ceil(measured.height), mapSide) + margin * 2
            let box = CGRect(x: margin, y: size.height - margin - height, width: size.width - margin * 2, height: height)
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.65).cgColor)
            context.cgContext.fill(box)
            if let map {
                let mapRect = CGRect(x: box.minX + margin, y: box.minY + margin, width: mapSide, height: mapSide)
                map.draw(in: mapRect)
                let markerSize = mapSide * 0.12
                let marker = CGRect(x: mapRect.midX-markerSize/2, y: mapRect.midY-markerSize/2, width: markerSize, height: markerSize)
                context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
                context.cgContext.fillEllipse(in: marker)
                context.cgContext.setStrokeColor(UIColor.white.cgColor)
                context.cgContext.setLineWidth(max(1, mapSide * 0.012))
                context.cgContext.strokeEllipse(in: marker)
            }
            let textRect = CGRect(x: box.minX + margin + mapSide + mapGap, y: box.minY + margin, width: textWidth, height: box.height - margin * 2)
            text.draw(in: textRect, withAttributes: attrs)
        }
        return result.jpegData(compressionQuality: 0.95)
    }
}

enum StampAddress {
    static func load(snapshot: StampSnapshot, queue: DispatchQueue, completion: @escaping (String?) -> Void) {
        guard snapshot.addressEnabled, let location = snapshot.location else { completion(nil); return }
        let geocoder = CLGeocoder()
        var finished = false
        let finish: (String?) -> Void = { address in
            guard !finished else { return }
            finished = true
            completion(address)
        }
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "pt_BR")) { placemarks, _ in
            let placemark = placemarks?.first
            let street = [placemark?.thoroughfare, placemark?.subThoroughfare].compactMap { $0 }.joined(separator: ", ")
            let parts = [street, placemark?.subLocality, placemark?.locality, placemark?.administrativeArea, placemark?.postalCode, placemark?.country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let address = parts.isEmpty ? nil : String(parts.joined(separator: ", ").prefix(240))
            queue.async { finish(address) }
        }
        queue.asyncAfter(deadline: .now() + 8) {
            guard !finished else { return }
            geocoder.cancelGeocode()
            finish(nil)
        }
    }
}

enum StampMap {
    // Completion is serialized onto the caller's queue and fires at most once.
    static func load(snapshot: StampSnapshot, queue: DispatchQueue, completion: @escaping (UIImage?) -> Void) {
        guard snapshot.mapEnabled, let location = snapshot.location else { completion(nil); return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 350, longitudinalMeters: 350)
        options.size = CGSize(width: 256, height: 256)
        let snapshotter = MKMapSnapshotter(options: options)
        var finished = false
        let finish: (UIImage?) -> Void = { image in
            guard !finished else { return }
            finished = true
            completion(image)
        }
        snapshotter.start(with: queue) { result, _ in finish(result?.image) }
        queue.asyncAfter(deadline: .now() + 8) {
            guard !finished else { return }
            snapshotter.cancel()
            finish(nil)
        }
    }
}
