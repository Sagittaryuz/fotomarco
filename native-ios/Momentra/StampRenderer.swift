import CoreLocation
import UIKit
import MapKit
import ImageIO
import CoreImage
import UniformTypeIdentifiers

enum MomentraPhotoStyle: String, CaseIterable, Identifiable {
    case natural = "Natural", brilliance = "Brilho", vivid = "Vibrante", soft = "Suave", dramatic = "Contraste", mono = "P&B", warm = "Quente"
    var id: String { rawValue }
    var filterName: String? {
        switch self {
        case .natural: return nil
        case .brilliance: return "CIPhotoEffectInstant"
        case .vivid: return "CIPhotoEffectChrome"
        case .soft: return "CIPhotoEffectFade"
        case .dramatic: return "CIPhotoEffectProcess"
        case .mono: return "CIPhotoEffectNoir"
        case .warm: return "CIPhotoEffectTransfer"
        }
    }
    var detail: String {
        switch self {
        case .natural: return "Mantém as cores originais da imagem."
        case .brilliance: return "Ilumina e aquece suavemente a fotografia."
        case .vivid: return "Realça as cores e o contraste."
        case .soft: return "Suaviza o contraste e as cores."
        case .dramatic: return "Destaca o contraste e as sombras."
        case .mono: return "Cria uma fotografia em preto e branco."
        case .warm: return "Acrescenta uma tonalidade quente."
        }
    }
    func apply(to image: UIImage) -> UIImage {
        guard let filterName, let filter = CIFilter(name: filterName), let input = CIImage(image: image) else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        guard let output = filter.outputImage, let cg = CIContext(options: nil).createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}

struct StampSnapshot {
    let capturedAt: Date
    let layout: StampLayout
    let gpsEnabled: Bool
    let mapEnabled: Bool
    let addressEnabled: Bool
    let cachedAddress: String?
    let title: String
    let note: String
    let logo: UIImage?
    let logoCorner: String
    let compact: Bool
    let position: String
    let horizontal: String
    let longDate: Bool
    let fontStyle: String
    let mapScale: String
    let mapCorner: String
    let pressure: PressureSample?
    let forecast: Forecast?
    let location: CLLocation?
    let heading: CLHeading?

    init(capturedAt: Date, gpsEnabled: Bool, mapEnabled: Bool = false, addressEnabled: Bool = false, cachedAddress: String? = nil, title: String = "", note: String = "", logo: UIImage? = nil, logoCorner: String = "auto", compact: Bool = false, position: String = "bottom", horizontal: String = "auto", longDate: Bool = false, fontStyle: String = "system", mapScale: String = "medium", mapCorner: String = "auto", pressure: PressureSample? = nil, forecast: Forecast? = nil, location: CLLocation?, heading: CLHeading?, layout: StampLayout = StampLayout()) {
        self.capturedAt = capturedAt
        self.layout = layout
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
        self.horizontal = ["auto", "left", "right"].contains(horizontal) ? horizontal : "auto"
        self.longDate = longDate
        self.fontStyle = ["system", "serif", "mono"].contains(fontStyle) ? fontStyle : "system"
        self.mapScale = ["small", "medium", "large"].contains(mapScale) ? mapScale : "medium"
        self.mapCorner = ["auto", "top-left", "top-right", "bottom-left", "bottom-right"].contains(mapCorner) ? mapCorner : "auto"
        self.pressure = pressure.flatMap { $0.isValid(at: capturedAt) ? $0 : nil }
        let validLocation: CLLocation?
        if gpsEnabled, let location, CLLocationCoordinate2DIsValid(location.coordinate),
           location.horizontalAccuracy >= 0, location.timestamp <= capturedAt,
           capturedAt.timeIntervalSince(location.timestamp) <= 60 {
            validLocation = location
        } else { validLocation = nil }
        self.location = validLocation
        self.cachedAddress = self.addressEnabled && validLocation != nil ? cachedAddress.map { String($0.prefix(240)) } : nil
        self.forecast = validLocation == nil || !layout.showsForecast ? nil : forecast.flatMap { $0.isValid(at: capturedAt) ? $0 : nil }
        if gpsEnabled, let heading, heading.headingAccuracy >= 0, heading.timestamp <= capturedAt,
           capturedAt.timeIntervalSince(heading.timestamp) <= 10 {
            self.heading = heading
        } else { self.heading = nil }
    }

    var lines: [String] { informationLines(address: nil) }

    func informationLines(address: String?) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = longDate ? "d 'de' MMMM 'de' yyyy 'às' HH'h'mm'min'ss's' 'GMT'XXXXX" : "dd/MM/yyyy HH:mm:ss 'GMT'XXXXX"
        var result: [String] = []
        let profile = [title, note].filter { !$0.isEmpty }.joined(separator: " · ")
        if !profile.isEmpty { result.append(profile) }
        if let address, !address.isEmpty { result.append(address.replacingOccurrences(of: "\n", with: " ")) }
        if let location {
            var geo = String(format: "Lat: %.6f  Lon: %.6f · Precisão: ±%.0f m", location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy)
            if location.verticalAccuracy >= 0 { geo += String(format: " · Altitude: %.1f m", location.altitude) }
            if let heading {
                let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
                if degrees >= 0 { geo += String(format: " · Direção: %.0f°", degrees) }
            }
            result.append(geo)
        } else {
            result.append(gpsEnabled ? "Localização indisponível" : "Localização desativada")
        }
        result.append(formatter.string(from: capturedAt))
        var values: [String] = []
        if let pressure { values.append(String(format: "Pressão local: %.1f hPa", pressure.hectopascals)) }
        if let forecast {
            if let temperature = forecast.temperatureC { values.append(String(format: "%.1f °C", temperature)) }
            if let humidity = forecast.humidityPercent { values.append(String(format: "%.0f%%", humidity)) }
            if let wind = forecast.windMetersPerSecond { values.append(String(format: "%.1f km/h", wind * 3.6)) }
            if let pressure = forecast.seaLevelPressureHpa { values.append(String(format: "%.1f hPa (nível do mar)", pressure)) }
        }
        if !values.isEmpty { result.append(values.joined(separator: " · ")) }
        return result
    }
}

enum PhotoAspect: String, CaseIterable {
    case standard = "4:3"
    case wide = "16:9"
    case square = "1:1"

    var landscapeRatio: CGFloat {
        switch self {
        case .standard: return 4 / 3
        case .wide: return 16 / 9
        case .square: return 1
        }
    }

    func fittedSize(in bounds: CGSize, landscape: Bool? = nil) -> CGSize? {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }
        let ratio = (landscape ?? (bounds.width >= bounds.height)) ? landscapeRatio : 1 / landscapeRatio
        let width = min(bounds.width, bounds.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    func previewFrame(in screen: CGSize, top: CGFloat, bottom: CGFloat) -> CGRect {
        let start = max(0, top)
        let end = min(screen.height, bottom)
        let available = CGSize(width: screen.width, height: end - start)
        let landscape = screen.width >= screen.height
        guard let reference = PhotoAspect.standard.fittedSize(in: available, landscape: landscape) else { return .zero }
        let anchor = start + (available.height - reference.height) / 2
        let remaining = CGSize(width: screen.width, height: end - anchor)
        guard let size = fittedSize(in: remaining, landscape: landscape) else { return .zero }
        return CGRect(x: (screen.width - size.width) / 2, y: anchor,
                      width: size.width, height: size.height)
    }

    func crop(in size: CGSize) -> CGRect? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let ratio = size.width >= size.height ? landscapeRatio : 1 / landscapeRatio
        let width = floor(min(size.width, size.height * ratio))
        let height = floor(min(size.height, size.width / ratio))
        guard width >= 1, height >= 1 else { return nil }
        return CGRect(x: (size.width-width)/2, y: (size.height-height)/2, width: width, height: height)
    }
}

enum StampRenderer {
    static func stampBox(imageSize: CGSize, height: CGFloat, margin: CGFloat, horizontal: String, position: String) -> CGRect? {
        guard imageSize.width > margin * 2, imageSize.height > margin * 2,
              height > 0, height <= imageSize.height - margin * 2 else { return nil }
        let width = horizontal == "auto" ? imageSize.width - margin * 2 : min(imageSize.width * 0.75, imageSize.width - margin * 2)
        let x = horizontal == "right" ? imageSize.width - margin - width : margin
        let y = position == "top" ? margin : imageSize.height - margin - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func logoRect(imageSize: CGSize, logoSize: CGSize, stamp: CGRect, margin: CGFloat, corner: String, stampPosition: String, additional: [CGRect] = []) -> CGRect? {
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
        let blockers = [stamp] + additional
        for _ in 0...blockers.count {
            let collisions = blockers.filter { rect.intersects($0) }
            if collisions.isEmpty { break }
            y = useTop ? (collisions.map(\.maxY).max() ?? y) + margin : (collisions.map(\.minY).min() ?? y) - margin - logoSize.height
            rect.origin.y = y
        }
        let safe = CGRect(x: margin, y: margin, width: imageSize.width - margin * 2, height: imageSize.height - margin * 2)
        return safe.contains(rect) && !blockers.contains(where: { rect.intersects($0) }) ? rect : nil
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
            if paragraph.lineBreakMode == .byTruncatingTail, fontSize > 4 {
                let longest = (text as String).components(separatedBy: "\n")
                    .map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
                if longest > width {
                    fontSize = max(4, floor(fontSize * min(0.9, width / longest)))
                    continue
                }
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
            let measured = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
            let height = ceil(measured.height) + 2
            if height <= maxHeight { return (font, height) }
            fontSize = floor(fontSize * 0.9)
        }
        return nil
    }

    static func availableSize(size: CGSize, anchor: StampPoint, margin: CGFloat) -> CGSize {
        let safeWidth = max(0, size.width - margin * 2), safeHeight = max(0, size.height - margin * 2)
        let x = min(1, max(0, CGFloat(anchor.x))), y = min(1, max(0, CGFloat(anchor.y)))
        return CGSize(width: safeWidth * (x < 0.5 ? 1 - x : x),
                      height: safeHeight * (y < 0.5 ? 1 - y : y))
    }

    static func positionedRect(size: CGSize, element: CGSize, centre: StampPoint, margin: CGFloat) -> CGRect {
        let available = availableSize(size: size, anchor: centre, margin: margin)
        let width = min(max(0, element.width), available.width), height = min(max(0, element.height), available.height)
        let x = margin + min(1, max(0, CGFloat(centre.x))) * max(0, size.width - margin * 2)
        let y = margin + min(1, max(0, CGFloat(centre.y))) * max(0, size.height - margin * 2)
        return CGRect(x: centre.x < 0.5 ? x : x - width, y: centre.y < 0.5 ? y : y - height,
                      width: width, height: height)
    }

    static func drawSeparate(snapshot: StampSnapshot, map: UIImage?, address: String?, size: CGSize, context: CGContext) -> Bool {
        let unit = min(size.width, size.height)
        let margin = unit * 0.025
        let layout = snapshot.layout
        if let map, layout.showsMap {
            let space = availableSize(size: size, anchor: layout.map, margin: margin)
            let side = min(space.width, space.height, unit * 0.5, unit * (snapshot.mapScale == "small" ? 0.14 : snapshot.mapScale == "large" ? 0.27 : 0.20) * CGFloat(layout.mapSize))
            let rect = positionedRect(size: size, element: CGSize(width: side, height: side), centre: layout.map, margin: margin)
            map.draw(in: rect)
            let markerSize = side * 0.12
            let marker = CGRect(x: rect.midX - markerSize / 2, y: rect.midY - markerSize / 2, width: markerSize, height: markerSize)
            context.setFillColor(UIColor.systemBlue.cgColor)
            context.fillEllipse(in: marker)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(max(1, side * 0.012))
            context.strokeEllipse(in: marker)
        }
        let lines = snapshot.informationLines(address: address)
        let text = lines.joined(separator: "\n") as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        switch layout.textAlignment {
        case "left": paragraph.alignment = .left
        case "center": paragraph.alignment = .center
        case "right": paragraph.alignment = .right
        default: paragraph.alignment = layout.information.x >= 0.5 ? .right : .left
        }
        if layout.showsInformation {
            let textSpace = availableSize(size: size, anchor: layout.information, margin: margin)
            let textWidth = max(1, min(textSpace.width, size.width * 0.60 * CGFloat(max(1, layout.informationSize))))
            guard let measured = fitText(text, width: textWidth, maxHeight: textSpace.height,
                                         initialSize: max(12, unit * (snapshot.compact ? 0.021 : 0.027) * CGFloat(layout.informationSize)),
                                         style: snapshot.fontStyle, paragraph: paragraph) else { return false }
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = max(1, unit * 0.002)
            shadow.shadowOffset = CGSize(width: 1, height: 1)
            let rect = positionedRect(size: size, element: CGSize(width: textWidth, height: measured.height),
                                      centre: layout.information, margin: margin)
            text.draw(in: rect, withAttributes: [.font: measured.font, .foregroundColor: UIColor.white,
                                                .paragraphStyle: paragraph, .shadow: shadow])
        }
        if layout.showsLogo, let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
            let space = availableSize(size: size, anchor: layout.logo, margin: margin)
            let maxSide = min(space.width, space.height, unit * 0.35, unit * 0.15 * CGFloat(layout.logoSize))
            let scale = min(maxSide / logo.size.width, maxSide / logo.size.height)
            let logoSize = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
            logo.draw(in: positionedRect(size: size, element: logoSize, centre: layout.logo, margin: margin))
        }
        return true
    }

    static func overlay(size: CGSize, snapshot: StampSnapshot, map: UIImage?, address: String?) -> UIImage? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        var fits = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            fits = drawStamp(snapshot: snapshot, map: map, address: address, size: size, context: context)
        }
        return fits ? image : nil
    }

    private static func drawStamp(snapshot: StampSnapshot, map: UIImage?, address: String?,
                                  size: CGSize, context: UIGraphicsImageRendererContext) -> Bool {
        var fits = true
        func drawContents() {
            // Do not rely solely on upstream callers to filter location-derived assets.
            let map = snapshot.mapEnabled && snapshot.location != nil ? map : nil
            let address = snapshot.addressEnabled && snapshot.location != nil ? address : nil
            if snapshot.layout.mode == .separate {
                fits = drawSeparate(snapshot: snapshot, map: map, address: address, size: size, context: context.cgContext)
                return
            }
            let unit = min(size.width, size.height)
            let margin = unit * 0.035
            let fontSize = max(12, unit * (snapshot.compact ? 0.021 : 0.027) * CGFloat(snapshot.layout.informationSize * snapshot.layout.combinedSize))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            switch snapshot.layout.textAlignment {
            case "center": paragraph.alignment = .center
            case "right": paragraph.alignment = .right
            default: paragraph.alignment = .left
            }
            let lines = snapshot.layout.showsInformation ? snapshot.informationLines(address: address) : []
            let text = lines.joined(separator: "\n") as NSString
            let mapFraction: CGFloat = snapshot.mapScale == "small" ? 0.14 : snapshot.mapScale == "large" ? 0.27 : 0.20
            let mapSide = map == nil ? 0 : min(unit * 0.4, unit * mapFraction * CGFloat(snapshot.layout.mapSize * snapshot.layout.combinedSize))
            let separateMap = map != nil && snapshot.mapCorner != "auto"
            let inlineMapSide = separateMap ? 0 : mapSide
            let mapGap = inlineMapSide == 0 ? 0 : margin
            guard let horizontalBox = stampBox(imageSize: size, height: 1, margin: margin,
                                                horizontal: snapshot.horizontal, position: snapshot.position) else { fits = false; return }
            let logoSize: CGSize?
            if snapshot.layout.showsLogo, let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
                let maxSide = min(unit * 0.35, unit * 0.15 * CGFloat(snapshot.layout.logoSize * snapshot.layout.combinedSize))
                let scale = min(maxSide / logo.size.width, maxSide / logo.size.height)
                logoSize = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
            } else { logoSize = nil }
            let inlineLogo = snapshot.logoCorner == "auto" ? logoSize : nil
            let textWidth = horizontalBox.width - margin * 2 - inlineMapSide - mapGap
                - (inlineLogo?.width ?? 0) - (inlineLogo == nil ? 0 : margin)
            let externalLogoHeight = inlineLogo == nil ? (logoSize?.height ?? 0) : 0
            let availableTextHeight = size.height - margin * (4 + (externalLogoHeight > 0 ? 1 : 0) + (separateMap ? 1 : 0))
                - externalLogoHeight - (separateMap ? mapSide : 0)
            guard let layout = fitText(text, width: textWidth, maxHeight: availableTextHeight,
                                       initialSize: fontSize, style: snapshot.fontStyle, paragraph: paragraph) else { fits = false; return }
            let attrs: [NSAttributedString.Key: Any] = [.font: layout.font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph]
            let height = max(layout.height, inlineMapSide, inlineLogo?.height ?? 0) + margin * 2
            guard let box = stampBox(imageSize: size, height: height, margin: margin,
                                     horizontal: snapshot.horizontal, position: snapshot.position) else { fits = false; return }
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.65).cgColor)
            context.cgContext.fill(box)
            var separateMapRect: CGRect?
            if let map {
                let mapRect: CGRect
                if separateMap {
                    guard let placement = StampRenderer.logoRect(imageSize: size, logoSize: CGSize(width: mapSide, height: mapSide),
                        stamp: box, margin: margin, corner: snapshot.mapCorner, stampPosition: snapshot.position) else { fits = false; return }
                    mapRect = placement
                    separateMapRect = placement
                } else {
                    mapRect = CGRect(x: box.minX + margin, y: box.minY + margin, width: mapSide, height: mapSide)
                }
                map.draw(in: mapRect)
                let markerSize = mapSide * 0.12
                let marker = CGRect(x: mapRect.midX-markerSize/2, y: mapRect.midY-markerSize/2, width: markerSize, height: markerSize)
                context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
                context.cgContext.fillEllipse(in: marker)
                context.cgContext.setStrokeColor(UIColor.white.cgColor)
                context.cgContext.setLineWidth(max(1, mapSide * 0.012))
                context.cgContext.strokeEllipse(in: marker)
            }
            let textRect = CGRect(x: box.minX + margin + inlineMapSide + mapGap, y: box.minY + margin, width: textWidth, height: box.height - margin * 2)
            text.draw(in: textRect, withAttributes: attrs)
            if snapshot.layout.showsLogo, let logo = snapshot.logo, let logoSize {
                let logoRect: CGRect
                if inlineLogo != nil {
                    logoRect = CGRect(x: box.maxX - margin - logoSize.width, y: box.minY + margin,
                                      width: logoSize.width, height: logoSize.height)
                } else {
                    guard let external = StampRenderer.logoRect(imageSize: size, logoSize: logoSize, stamp: box, margin: margin,
                                                  corner: snapshot.logoCorner, stampPosition: snapshot.position,
                                                  additional: separateMapRect.map { [$0] } ?? []) else { fits = false; return }
                    logoRect = external
                }
                logo.draw(in: logoRect)
            }
        }
        drawContents()
        return fits
    }

    static func render(_ data: Data, aspect: PhotoAspect?, snapshot: StampSnapshot?, map: UIImage? = nil, address: String? = nil, style: MomentraPhotoStyle = .natural) -> Data? {
        guard let sourceImage = UIImage(data: data) else { return nil }
        let image = style.apply(to: sourceImage)
        let sourceSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard sourceSize.width > 0, sourceSize.height > 0,
              sourceSize.width.isFinite, sourceSize.height.isFinite else { return nil }
        let crop: CGRect
        if let aspect {
            guard let adjusted = aspect.crop(in: sourceSize) else { return nil }
            crop = adjusted
        } else {
            crop = CGRect(origin: .zero, size: sourceSize)
        }
        let size = crop.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var fits = true
        let result = renderer.image { context in
            image.draw(in: CGRect(x: -crop.minX, y: -crop.minY, width: sourceSize.width, height: sourceSize.height))
            guard let snapshot else { return }
            fits = drawStamp(snapshot: snapshot, map: map, address: address, size: size, context: context)
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
        if snapshot?.forecast != nil, snapshot?.layout.showsInformation == true {
            result[kCGImagePropertyIPTCDictionary as String] = [
                kCGImagePropertyIPTCSource as String: "https://momentra-camera.vercel.app/privacidade.html#creditos"
            ]
        }
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
    static func format(_ placemark: CLPlacemark) -> String? {
        let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: ", ")
        let parts = [street, placemark.subLocality, placemark.locality, placemark.administrativeArea, placemark.postalCode, placemark.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : String(parts.joined(separator: ", ").prefix(240))
    }

    static func load(snapshot: StampSnapshot, queue: DispatchQueue, completion: @escaping (String?) -> Void) {
        guard snapshot.addressEnabled, let location = snapshot.location else { completion(nil); return }
        if let cached = snapshot.cachedAddress { completion(cached); return }
        let geocoder = CLGeocoder()
        var finished = false
        let finish: (String?) -> Void = { address in
            guard !finished else { return }
            finished = true
            completion(address)
        }
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "pt_BR")) { placemarks, _ in
            let address = placemarks?.first.flatMap(format)
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
        options.mapType = snapshot.layout.mapStyle == .satellite ? .satellite : .standard
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
