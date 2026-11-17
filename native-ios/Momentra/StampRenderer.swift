import CoreLocation
import UIKit
import MapKit
import ImageIO
import UniformTypeIdentifiers

struct StampSnapshot {
    let capturedAt: Date
    let gpsEnabled: Bool
    let mapEnabled: Bool
    let addressEnabled: Bool
    let title: String
    let note: String
    let logo: UIImage?
    let logoCorner: String
    let compact: Bool
    let position: String
    let longDate: Bool
    let fontStyle: String
    let mapScale: String
    let pressure: PressureSample?
    let forecast: Forecast?
    let location: CLLocation?
    let heading: CLHeading?

    init(capturedAt: Date, gpsEnabled: Bool, mapEnabled: Bool = false, addressEnabled: Bool = false, title: String = "", note: String = "", logo: UIImage? = nil, logoCorner: String = "auto", compact: Bool = false, position: String = "bottom", longDate: Bool = false, fontStyle: String = "system", mapScale: String = "medium", pressure: PressureSample? = nil, forecast: Forecast? = nil, location: CLLocation?, heading: CLHeading?) {
        self.capturedAt = capturedAt
        self.gpsEnabled = gpsEnabled
        self.mapEnabled = gpsEnabled && mapEnabled
        self.addressEnabled = gpsEnabled && addressEnabled
        func clean(_ text: String, limit: Int) -> String {
            let singleLine = text.components(separatedBy: .newlines).joined(separator: " ").replacingOccurrences(of: "\t", with: " ")
            return String(singleLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        }
        self.title = clean(title, limit: 40)
        self.note = clean(note, limit: 96)
        self.logo = logo
        self.logoCorner = ["auto", "top-left", "top-right", "bottom-left", "bottom-right"].contains(logoCorner) ? logoCorner : "auto"
        self.compact = compact
        self.position = position == "top" ? "top" : "bottom"
        self.longDate = longDate
        self.fontStyle = ["system", "serif", "mono"].contains(fontStyle) ? fontStyle : "system"
        self.mapScale = ["small", "medium", "large"].contains(mapScale) ? mapScale : "medium"
        self.pressure = pressure.flatMap { $0.isValid(at: capturedAt) ? $0 : nil }
        let validLocation: CLLocation?
        if gpsEnabled, let location, CLLocationCoordinate2DIsValid(location.coordinate),
           location.horizontalAccuracy >= 0, location.timestamp <= capturedAt,
           capturedAt.timeIntervalSince(location.timestamp) <= 60 {
            validLocation = location
        } else { validLocation = nil }
        self.location = validLocation
        self.forecast = validLocation == nil ? nil : forecast.flatMap { $0.isValid(at: capturedAt) ? $0 : nil }
        if gpsEnabled, let heading, heading.headingAccuracy >= 0, heading.timestamp <= capturedAt,
           capturedAt.timeIntervalSince(heading.timestamp) <= 10 {
            self.heading = heading
        } else { self.heading = nil }
    }

    var lines: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = longDate ? "d 'de' MMMM 'de' yyyy 'às' HH'h'mm'min'ss's' 'GMT'XXXXX" : "dd/MM/yyyy HH:mm:ss 'GMT'XXXXX"
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
        if let pressure { result.append(String(format: "Pressão local: %.1f hPa", pressure.hectopascals)) }
        if let forecast {
            var values: [String] = []
            if let temperature = forecast.temperatureC { values.append(String(format: "%.1f °C", temperature)) }
            if let humidity = forecast.humidityPercent { values.append(String(format: "%.0f%%", humidity)) }
            if let wind = forecast.windMetersPerSecond { values.append(String(format: "%.1f km/h", wind * 3.6)) }
            if let pressure = forecast.seaLevelPressureHpa { values.append(String(format: "%.1f hPa (nível do mar)", pressure)) }
            if !values.isEmpty {
                result.append("Previsão válida em " + formatter.string(from: forecast.validAt) + ": " + values.joined(separator: " · "))
                result.append("MET Norway · CC BY 4.0 · creativecommons.org/licenses/by/4.0/")
            }
        }
        if !note.isEmpty { result.insert(note, at: 0) }
        if !title.isEmpty { result.insert(title, at: 0) }
        return result
    }
}

enum PhotoAspect: String, CaseIterable {
    case standard = "4:3"
    case wide = "16:9"

    func fittedSize(in bounds: CGSize) -> CGSize? {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }
        let landscapeRatio: CGFloat = self == .standard ? 4 / 3 : 16 / 9
        let ratio = bounds.width >= bounds.height ? landscapeRatio : 1 / landscapeRatio
        let width = min(bounds.width, bounds.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    func crop(in size: CGSize) -> CGRect? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let landscapeRatio: CGFloat = self == .standard ? 4 / 3 : 16 / 9
        let ratio = size.width >= size.height ? landscapeRatio : 1 / landscapeRatio
        let width = floor(min(size.width, size.height * ratio))
        let height = floor(min(size.height, size.width / ratio))
        guard width >= 1, height >= 1 else { return nil }
        return CGRect(x: (size.width-width)/2, y: (size.height-height)/2, width: width, height: height)
    }
}

enum StampRenderer {
    static func logoRect(imageSize: CGSize, logoSize: CGSize, stamp: CGRect, margin: CGFloat, corner: String, stampPosition: String) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0, logoSize.width > 0, logoSize.height > 0, margin >= 0 else { return nil }
        let useLeft = corner.hasSuffix("-left")
        let useTop = corner == "auto" ? stampPosition == "top" : corner.hasPrefix("top-")
        let x = useLeft ? margin : imageSize.width - margin - logoSize.width
        var y: CGFloat
        if corner == "auto" {
            y = useTop ? min(imageSize.height - margin - logoSize.height, stamp.maxY + margin) : max(margin, stamp.minY - margin - logoSize.height)
        } else {
            y = useTop ? margin : imageSize.height - margin - logoSize.height
        }
        var rect = CGRect(origin: CGPoint(x: x, y: y), size: logoSize)
        if rect.intersects(stamp) {
            y = useTop ? stamp.maxY + margin : stamp.minY - margin - logoSize.height
            rect.origin.y = y
        }
        let safe = CGRect(x: margin, y: margin, width: imageSize.width - margin * 2, height: imageSize.height - margin * 2)
        return safe.contains(rect) && !rect.intersects(stamp) ? rect : nil
    }

    static func fitText(_ text: NSString, width: CGFloat, maxHeight: CGFloat, initialSize: CGFloat,
                        style: String, paragraph: NSParagraphStyle) -> (font: UIFont, height: CGFloat)? {
        guard width > 0, maxHeight > 0, initialSize.isFinite else { return nil }
        var fontSize = initialSize
        while fontSize >= 4 {
            let system = UIFont.systemFont(ofSize: fontSize, weight: .medium)
            let font: UIFont
            if style == "mono" { font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .medium) }
            else if style == "serif", let descriptor = system.fontDescriptor.withDesign(.serif) { font = UIFont(descriptor: descriptor, size: fontSize) }
            else { font = system }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
            let measured = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
            let height = ceil(measured.height) + 2
            if height <= maxHeight { return (font, height) }
            fontSize = floor(fontSize * 0.9)
        }
        return nil
    }

    static func render(_ data: Data, aspect: PhotoAspect, snapshot: StampSnapshot?, map: UIImage? = nil, address: String? = nil) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let sourceSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard let crop = aspect.crop(in: sourceSize) else { return nil }
        let size = crop.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var fits = true
        let result = renderer.image { context in
            image.draw(in: CGRect(x: -crop.minX, y: -crop.minY, width: sourceSize.width, height: sourceSize.height))
            guard let snapshot else { return }
            let unit = min(size.width, size.height)
            let margin = unit * 0.035
            let fontSize = max(12, unit * (snapshot.compact ? 0.021 : 0.027))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let lines = (address.map { [$0] } ?? []) + snapshot.lines
            let text = lines.joined(separator: "\n") as NSString
            let mapFraction: CGFloat = snapshot.mapScale == "small" ? 0.14 : snapshot.mapScale == "large" ? 0.27 : 0.20
            let mapSide = map == nil ? 0 : unit * mapFraction
            let mapGap = map == nil ? 0 : margin
            let textWidth = size.width - margin * 4 - mapSide - mapGap
            let logoSize: CGSize?
            if let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
                let maxSide = unit * 0.15
                let scale = min(maxSide / logo.size.width, maxSide / logo.size.height)
                logoSize = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
            } else { logoSize = nil }
            let availableTextHeight = size.height - margin * (logoSize == nil ? 4 : 5) - (logoSize?.height ?? 0)
            guard let layout = fitText(text, width: textWidth, maxHeight: availableTextHeight,
                                       initialSize: fontSize, style: snapshot.fontStyle, paragraph: paragraph) else { fits = false; return }
            let attrs: [NSAttributedString.Key: Any] = [.font: layout.font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph]
            let height = max(layout.height, mapSide) + margin * 2
            let boxY = snapshot.position == "top" ? margin : size.height - margin - height
            let box = CGRect(x: margin, y: boxY, width: size.width - margin * 2, height: height)
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
            if let logo = snapshot.logo, let logoSize {
                guard let logoRect = StampRenderer.logoRect(imageSize: size, logoSize: logoSize, stamp: box, margin: margin,
                                              corner: snapshot.logoCorner, stampPosition: snapshot.position) else { fits = false; return }
                logo.draw(in: logoRect)
            }
        }
        guard fits, let outputImage = result.cgImage,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let properties = PhotoMetadata.properties(original: original, snapshot: snapshot, size: size)
        CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

enum PhotoMetadata {
    static func properties(original: [String: Any], snapshot: StampSnapshot?, size: CGSize) -> [String: Any] {
        var result: [String: Any] = [
            kCGImagePropertyOrientation as String: 1,
            kCGImagePropertyPixelWidth as String: Int(size.width),
            kCGImagePropertyPixelHeight as String: Int(size.height),
            kCGImageDestinationLossyCompressionQuality as String: 0.95
        ]
        // A whitelist prevents old GPS, thumbnails, and arbitrary location metadata from leaking.
        func copyFields(_ dictionary: CFString, _ keys: [CFString]) {
            guard let source = original[dictionary as String] as? [String: Any] else { return }
            var selected: [String: Any] = [:]
            for key in keys { if let value = source[key as String] { selected[key as String] = value } }
            if !selected.isEmpty { result[dictionary as String] = selected }
        }
        copyFields(kCGImagePropertyTIFFDictionary, [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware])
        copyFields(kCGImagePropertyExifDictionary, [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifExposureTime, kCGImagePropertyExifFNumber, kCGImagePropertyExifISOSpeedRatings, kCGImagePropertyExifFocalLength, kCGImagePropertyExifLensModel])
        if let location = snapshot?.location, snapshot?.gpsEnabled == true {
            let latitude = location.coordinate.latitude, longitude = location.coordinate.longitude
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy:MM:dd"
            let date = formatter.string(from: location.timestamp)
            formatter.dateFormat = "HH:mm:ss.SSS"
            var gps: [String: Any] = [
                kCGImagePropertyGPSLatitude as String: abs(latitude),
                kCGImagePropertyGPSLatitudeRef as String: latitude < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude as String: abs(longitude),
                kCGImagePropertyGPSLongitudeRef as String: longitude < 0 ? "W" : "E",
                kCGImagePropertyGPSDateStamp as String: date,
                kCGImagePropertyGPSTimeStamp as String: formatter.string(from: location.timestamp)
            ]
            if location.verticalAccuracy >= 0 {
                gps[kCGImagePropertyGPSAltitude as String] = abs(location.altitude)
                gps[kCGImagePropertyGPSAltitudeRef as String] = location.altitude < 0 ? 1 : 0
            }
            result[kCGImagePropertyGPSDictionary as String] = gps
        }
        return result
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
