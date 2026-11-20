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
    let extraLogos: [UIImage?]
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

    init(capturedAt: Date, gpsEnabled: Bool, mapEnabled: Bool = false, addressEnabled: Bool = false, cachedAddress: String? = nil, title: String = "", note: String = "", logo: UIImage? = nil, extraLogos: [UIImage?] = [], logoCorner: String = "auto", compact: Bool = false, position: String = "bottom", horizontal: String = "auto", longDate: Bool = false, fontStyle: String = "system", mapScale: String = "medium", mapCorner: String = "auto", pressure: PressureSample? = nil, forecast: Forecast? = nil, location: CLLocation?, heading: CLHeading?, layout: StampLayout = StampLayout()) {
        self.capturedAt = capturedAt
        self.layout = layout
        self.gpsEnabled = gpsEnabled
        self.mapEnabled = gpsEnabled && mapEnabled && (layout.template == .original || layout.template.usesMap)
        self.addressEnabled = gpsEnabled && addressEnabled
        func clean(_ text: String, limit: Int) -> String {
            let singleLine = text.components(separatedBy: .newlines).joined(separator: " ").replacingOccurrences(of: "\t", with: " ")
            return String(singleLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        }
        self.title = clean(title, limit: 40)
        self.note = clean(note, limit: 96)
        self.logo = logo
        self.extraLogos = Array(extraLogos.prefix(2))
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

    /// Real capture data for fixed templates. Missing sensor data stays absent.
    func templateContent(address: String?) -> StampTemplateContent {
        let date = DateFormatter()
        date.locale = Locale(identifier: "pt_BR")
        date.dateFormat = "dd/MM/yyyy"
        let time = DateFormatter()
        time.locale = date.locale
        time.dateFormat = "HH:mm"
        let shortDate = DateFormatter()
        shortDate.locale = date.locale
        shortDate.dateFormat = "dd MMM"
        let year = DateFormatter()
        year.locale = date.locale
        year.dateFormat = "yyyy"
        let address = addressEnabled && location != nil ? address : nil
        let coordinate = location.map { fix in
            String(format: "%.5f°%@, %.5f°%@", abs(fix.coordinate.latitude), fix.coordinate.latitude < 0 ? "S" : "N",
                   abs(fix.coordinate.longitude), fix.coordinate.longitude < 0 ? "O" : "L")
        }
        var values: [String: String] = [:]
        for field in layout.template.fields {
            let value = layout.templateValue(field).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { values[field] = value }
        }
        return StampTemplateContent(template: layout.template, date: date.string(from: capturedAt),
                                    time: time.string(from: capturedAt), dayMonth: shortDate.string(from: capturedAt),
                                    year: year.string(from: capturedAt), address: address,
                                    coordinate: coordinate, customFields: values)
    }

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

struct StampTemplateContent {
    let template: StampLayout.Template
    let date: String
    let time: String
    let dayMonth: String
    let year: String
    let address: String?
    let coordinate: String?
    let customFields: [String: String]
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
    static func condensedStampFont(size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? "AvenirNextCondensed-DemiBold" : "AvenirNextCondensed-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }
    static func drawPatrol(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        let yellow = UIColor(red: 1, green: 0.84, blue: 0.16, alpha: 1)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        context.saveGState(); defer { context.restoreGState() }
        context.setFillColor(UIColor(red: 0.20, green: 0.29, blue: 0.72, alpha: 0.97).cgColor); context.fill(box)
        let header = CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height * 0.40)
        context.setFillColor(UIColor(red: 0.16, green: 0.20, blue: 0.42, alpha: 1).cgColor); context.fill(header)
        context.setFillColor(yellow.cgColor)
        context.fill(CGRect(x: header.minX, y: header.maxY - max(1, box.height * 0.018), width: header.width, height: max(1, box.height * 0.018)))
        let shield = CGRect(x: box.minX + box.width * 0.05, y: box.minY + box.height * 0.06, width: box.height * 0.27, height: box.height * 0.27)
        if let icon = UIImage(systemName: "checkmark.shield")?.withTintColor(yellow, renderingMode: .alwaysOriginal) { icon.draw(in: shield) }
        let title = content.customFields["Título"] ?? "Segurança"
        (title as NSString).draw(in: CGRect(x: shield.maxX + box.width * 0.04, y: box.minY + box.height * 0.07, width: box.maxX - shield.maxX - box.width * 0.07, height: box.height * 0.27),
            withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.21, weight: .bold), .foregroundColor: yellow, .paragraphStyle: paragraph])
        (content.time as NSString).draw(in: CGRect(x: box.minX + box.width * 0.06, y: box.minY + box.height * 0.44, width: box.width * 0.30, height: box.height * 0.27),
            withAttributes: [.font: fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: box.height * 0.22, weight: .medium), sample: "88:88", width: box.width * 0.30), .foregroundColor: yellow, .paragraphStyle: paragraph])
        (content.date as NSString).draw(in: CGRect(x: box.minX + box.width * 0.39, y: box.minY + box.height * 0.48, width: box.width * 0.56, height: box.height * 0.20),
            withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.14, weight: .semibold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        context.setFillColor(UIColor.systemRed.cgColor)
        context.fill(CGRect(x: box.minX + box.width * 0.06, y: box.minY + box.height * 0.76, width: max(1, box.width * 0.012), height: box.height * 0.15))
        ((content.address ?? "") as NSString).draw(in: CGRect(x: box.minX + box.width * 0.09, y: box.minY + box.height * 0.73, width: box.width * 0.87, height: box.height * 0.22),
            withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.14, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        return true
    }
    static func fittedFixedFont(_ font: UIFont, sample: String, width: CGFloat) -> UIFont {
        guard width > 0 else { return font }
        var result = font
        for _ in 0..<12 {
            let measured = (sample as NSString).size(withAttributes: [.font: result]).width
            guard measured > width, measured > 0 else { return result }
            let nextSize = min(result.pointSize - 0.1, result.pointSize * width / measured * 0.95)
            guard nextSize > 0 else { break }
            result = result.withSize(nextSize)
        }
        return result
    }
    static func drawConstruction(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        context.saveGState(); defer { context.restoreGState() }
        let blue = UIColor(red: 0.15, green: 0.24, blue: 0.59, alpha: 0.96)
        context.setFillColor(blue.cgColor)
        context.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height * 0.52))
        context.setFillColor(UIColor(white: 0.84, alpha: 0.95).cgColor)
        context.fill(CGRect(x: box.minX, y: box.minY + box.height * 0.52, width: box.width, height: box.height * 0.48))
        let images = [snapshot.logo] + Array(snapshot.extraLogos.prefix(2))
        for index in 0..<3 {
            let cell = CGRect(x: box.minX + box.width * (0.03 + CGFloat(index) * 0.32), y: box.minY + box.height * 0.04, width: box.width * 0.29, height: box.height * 0.19)
            context.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor); context.fill(cell)
            if index < images.count, let image = images[index], image.size.width > 0, image.size.height > 0 {
                let scale = min(cell.width / image.size.width, cell.height / image.size.height) * 0.9
                let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: cell.midX - fitted.width / 2, y: cell.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
            }
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let title = content.customFields["Título"] ?? "Registro de Construção"
        (title as NSString).draw(in: CGRect(x: box.minX + box.width * 0.04, y: box.minY + box.height * 0.28, width: box.width * 0.92, height: box.height * 0.21),
            withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.17, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        let rows = [("Descrição", content.customFields["Descrição"] ?? ""), ("Hora", content.date + " " + content.time)]
        for index in rows.indices {
            let y = box.minY + box.height * (0.57 + CGFloat(index) * 0.21)
            (rows[index].0 as NSString).draw(in: CGRect(x: box.minX + box.width * 0.04, y: y, width: box.width * 0.32, height: box.height * 0.19),
                withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.12, weight: .semibold), .foregroundColor: UIColor.darkGray, .paragraphStyle: paragraph])
            (rows[index].1 as NSString).draw(in: CGRect(x: box.minX + box.width * 0.38, y: y, width: box.width * 0.58, height: box.height * 0.19),
                withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.12, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        }
        return true
    }
    static func drawShippingTemplate(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        context.saveGState(); defer { context.restoreGState() }
        let banner = CGRect(x: box.minX, y: box.minY, width: box.width * 0.9, height: box.height * 0.34)
        context.setFillColor(UIColor.white.withAlphaComponent(0.95).cgColor); context.fill(banner)
        let code = CGRect(x: banner.minX, y: banner.minY, width: banner.width * 0.38, height: banner.height)
        context.setFillColor(UIColor.systemYellow.cgColor); context.fill(code)
        ((content.customFields["Código"] ?? "") as NSString).draw(in: code.insetBy(dx: code.width * 0.04, dy: code.height * 0.12),
            withAttributes: [.font: UIFont.systemFont(ofSize: banner.height * 0.47, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        (content.time as NSString).draw(in: CGRect(x: banner.minX + banner.width * 0.40, y: banner.minY + banner.height * 0.1, width: banner.width * 0.35, height: banner.height * 0.8),
            withAttributes: [.font: fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: banner.height * 0.55, weight: .bold), sample: "88:88", width: banner.width * 0.35), .foregroundColor: UIColor.systemBlue, .paragraphStyle: paragraph])
        let imageBox = CGRect(x: banner.minX + banner.width * 0.77, y: banner.minY + banner.height * 0.08, width: banner.width * 0.21, height: banner.height * 0.84)
        if let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
            let factor = min(imageBox.width / logo.size.width, imageBox.height / logo.size.height)
            let fitted = CGSize(width: logo.size.width * factor, height: logo.size.height * factor)
            logo.draw(in: CGRect(x: imageBox.midX - fitted.width / 2, y: imageBox.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
        }
        let bodyY = banner.maxY + box.height * 0.06
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fill(CGRect(x: box.minX, y: bodyY, width: max(1, box.width * 0.008), height: box.maxY - bodyY))
        let eta = content.customFields["Previsão de entrega"].map { "Previsão: " + $0 } ?? ""
        let lines = [content.date, eta, content.address ?? ""]
        for index in lines.indices {
            (lines[index] as NSString).draw(in: CGRect(x: box.minX + box.width * 0.04, y: bodyY + CGFloat(index) * box.height * 0.18, width: box.width * 0.95, height: box.height * 0.18),
                withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.12, weight: .medium), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        return true
    }
    static func drawPortrait(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        context.saveGState(); defer { context.restoreGState() }
        (content.time as NSString).draw(in: CGRect(x: box.minX, y: box.minY + box.height * 0.05, width: box.width * 0.4, height: box.height * 0.56),
            withAttributes: [.font: fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: box.height * 0.43, weight: .medium), sample: "88:88", width: box.width * 0.4), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fill(CGRect(x: box.minX + box.width * 0.41, y: box.minY + box.height * 0.1, width: max(1, box.width * 0.008), height: box.height * 0.43))
        (content.date as NSString).draw(in: CGRect(x: box.minX + box.width * 0.44, y: box.minY + box.height * 0.18, width: box.width * 0.25, height: box.height * 0.22),
            withAttributes: [.font: fittedFixedFont(UIFont.systemFont(ofSize: box.height * 0.13, weight: .semibold), sample: "88/88/8888", width: box.width * 0.25), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        ((content.address ?? "") as NSString).draw(in: CGRect(x: box.minX, y: box.minY + box.height * 0.67, width: box.width * 0.69, height: box.height * 0.23),
            withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.14, weight: .medium), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        let portraitBox = CGRect(x: box.minX + box.width * 0.70, y: box.minY, width: box.width * 0.30, height: box.height * 0.85)
        if let portrait = snapshot.logo, portrait.size.width > 0, portrait.size.height > 0 {
            let scale = min(portraitBox.width / portrait.size.width, portraitBox.height / portrait.size.height)
            let fitted = CGSize(width: portrait.size.width * scale, height: portrait.size.height * scale)
            portrait.draw(in: CGRect(x: portraitBox.midX - fitted.width / 2, y: portraitBox.maxY - fitted.height, width: fitted.width, height: fitted.height))
        }
        if let name = content.customFields["Nome"], !name.isEmpty {
            let caption = CGRect(x: portraitBox.minX, y: box.minY + box.height * 0.85, width: portraitBox.width, height: box.height * 0.15)
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.9).cgColor); context.fill(caption)
            let centered = NSMutableParagraphStyle(); centered.alignment = .center; centered.lineBreakMode = .byTruncatingTail
            (name as NSString).draw(in: caption, withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.10, weight: .medium), .foregroundColor: UIColor.white, .paragraphStyle: centered])
        }
        return true
    }
    static func drawLargeMap(snapshot: StampSnapshot, map: UIImage?, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        context.saveGState()
        defer { context.restoreGState() }
        if snapshot.mapEnabled, let map {
            map.draw(in: box)
            let marker = box.height * 0.09
            context.setFillColor(UIColor.systemBlue.cgColor)
            context.fillEllipse(in: CGRect(x: box.midX - marker / 2, y: box.midY - marker / 2, width: marker, height: marker))
            context.setStrokeColor(UIColor.white.cgColor); context.setLineWidth(max(1, marker * 0.12))
            context.strokeEllipse(in: CGRect(x: box.midX - marker / 2, y: box.midY - marker / 2, width: marker, height: marker))
        }
        let cameraBadge = CGRect(x: box.maxX - box.width * 0.24, y: box.minY + box.height * 0.04,
                                 width: box.width * 0.21, height: box.height * 0.42)
        context.setFillColor(UIColor(white: 0.20, alpha: 0.8).cgColor)
        context.fill(cameraBadge)
        if let icon = UIImage(systemName: "camera.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let side = min(cameraBadge.width, cameraBadge.height) * 0.55
            icon.draw(in: CGRect(x: cameraBadge.midX - side / 2, y: cameraBadge.midY - side / 2, width: side, height: side))
        }
        let strip = CGRect(x: box.minX, y: box.minY + box.height * 0.64, width: box.width, height: box.height * 0.36)
        context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor); context.fill(strip)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let lines = [content.coordinate ?? "", content.date + " " + content.time]
        for index in lines.indices {
            let font = index == 0
                ? fittedFixedFont(UIFont.systemFont(ofSize: box.height * 0.12, weight: .medium), sample: "88.88888°S, 188.88888°O", width: strip.width * 0.67)
                : UIFont.systemFont(ofSize: box.height * 0.12, weight: .medium)
            (lines[index] as NSString).draw(in: CGRect(x: strip.minX + box.width * 0.04, y: strip.minY + CGFloat(index) * strip.height * 0.5, width: strip.width * 0.67, height: strip.height * 0.48),
                withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        if let heading = snapshot.heading {
            let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            if degrees >= 0 {
                let right = NSMutableParagraphStyle(); right.alignment = .right
                (String(format: "%.0f°", degrees) as NSString).draw(in: CGRect(x: strip.midX, y: strip.minY, width: strip.width * 0.46, height: strip.height * 0.48),
                    withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.12), .foregroundColor: UIColor.white, .paragraphStyle: right])
            }
        }
        if let temperature = snapshot.forecast?.temperatureC {
            let right = NSMutableParagraphStyle(); right.alignment = .right
            (String(format: "%.0f °C", temperature) as NSString).draw(in: CGRect(x: strip.midX, y: strip.minY + strip.height * 0.5, width: strip.width * 0.46, height: strip.height * 0.48),
                withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.12), .foregroundColor: UIColor.white, .paragraphStyle: right])
        }
        return true
    }
    static func drawInspection(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let font = UIFont.systemFont(ofSize: box.height * 0.12, weight: .medium)
        context.saveGState()
        defer { context.restoreGState() }
        func label(_ text: String, rect: CGRect, background: UIColor?) {
            if let background { context.setFillColor(background.cgColor); context.fill(rect) }
            (text as NSString).draw(in: rect.insetBy(dx: box.width * 0.015, dy: box.height * 0.02),
                withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        if let heading = snapshot.heading {
            let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            if degrees >= 0 { label(String(format: "%.0f°", degrees), rect: CGRect(x: box.minX, y: box.minY, width: box.width * 0.36, height: box.height * 0.21), background: .systemOrange) }
        }
        if let location = snapshot.location, location.verticalAccuracy >= 0 {
            label(String(format: "%.0f m", location.altitude), rect: CGRect(x: box.minX + box.width * 0.40, y: box.minY, width: box.width * 0.23, height: box.height * 0.21), background: UIColor(white: 0.2, alpha: 0.7))
        }
        if let coordinate = content.coordinate {
            label(coordinate, rect: CGRect(x: box.minX, y: box.minY + box.height * 0.27, width: box.width * 0.84, height: box.height * 0.21), background: UIColor(white: 0.2, alpha: 0.7))
        }
        context.setFillColor(UIColor.systemOrange.cgColor)
        context.fill(CGRect(x: box.minX, y: box.minY + box.height * 0.55, width: max(1, box.width * 0.008), height: box.height * 0.45))
        let title = content.customFields["Título"]
        let lines = [content.date + " " + content.time, content.address ?? "", title ?? ""]
        for index in lines.indices {
            label(lines[index], rect: CGRect(x: box.minX + box.width * 0.035, y: box.minY + box.height * (0.55 + CGFloat(index) * 0.15), width: box.width * 0.94, height: box.height * 0.16), background: nil)
        }
        return true
    }
    static func drawProofTemplate(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        let delivery = snapshot.layout.template == .deliveryProof
        let color = delivery ? UIColor(red: 0.88, green: 0.04, blue: 0.04, alpha: 1) : UIColor(red: 0.23, green: 0.10, blue: 0.07, alpha: 1)
        let banner = CGRect(x: box.minX, y: box.minY, width: box.width * 0.82, height: box.height * 0.37)
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(color.cgColor)
        context.fill(banner)
        let logoBox = CGRect(x: banner.minX + banner.height * 0.08, y: banner.minY + banner.height * 0.08, width: banner.height * 0.84, height: banner.height * 0.84)
        if let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
            let factor = min(logoBox.width / logo.size.width, logoBox.height / logo.size.height)
            let fitted = CGSize(width: logo.size.width * factor, height: logo.size.height * factor)
            logo.draw(in: CGRect(x: logoBox.midX - fitted.width / 2, y: logoBox.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (content.time as NSString).draw(in: CGRect(x: logoBox.maxX + banner.height * 0.12, y: banner.minY + banner.height * 0.06, width: banner.width * 0.42, height: banner.height * 0.84),
            withAttributes: [.font: fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: banner.height * 0.68, weight: .medium), sample: "88:88", width: banner.width * 0.42), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        let badge = CGRect(x: banner.maxX - banner.height * 0.72, y: banner.minY + banner.height * 0.16, width: banner.height * 0.62, height: banner.height * 0.62)
        if !delivery {
            context.setFillColor(UIColor.systemYellow.cgColor)
            context.fillEllipse(in: badge)
        }
        let iconName = delivery ? "shippingbox.fill" : "checkmark"
        let iconColor: UIColor = delivery ? .white : .black
        if let icon = UIImage(systemName: iconName)?.withTintColor(iconColor, renderingMode: .alwaysOriginal) {
            icon.draw(in: badge.insetBy(dx: badge.width * 0.22, dy: badge.height * 0.22))
        }
        let bodyY = banner.maxY + box.height * 0.07
        context.setFillColor((delivery ? UIColor.systemRed : UIColor.systemYellow).cgColor)
        context.fill(CGRect(x: box.minX, y: bodyY, width: max(1, box.width * 0.008), height: box.maxY - bodyY))
        let lines = [content.date, content.address ?? ""]
        for index in lines.indices {
            (lines[index] as NSString).draw(in: CGRect(x: box.minX + box.width * 0.04, y: bodyY + CGFloat(index) * box.height * 0.22, width: box.width * 0.94, height: box.height * 0.21),
                withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.14, weight: .medium), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        return true
    }
    static func drawBannerTemplate(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        let template = snapshot.layout.template
        let patrol = template == .patrol
        let clean = template == .clean
        let blue = UIColor(red: 0.05, green: 0.28, blue: 0.68, alpha: 0.96)
        let yellow = UIColor(red: 1, green: 0.75, blue: 0.12, alpha: 1)
        let headline = content.customFields[clean ? "Texto" : "Título"] ?? (clean ? "Limpo" : patrol ? "Segurança" : "Ponto Eletrônico")
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        context.saveGState()
        defer { context.restoreGState() }
        let bannerY = box.minY + (clean ? box.height * 0.13 : 0)
        let banner = CGRect(x: box.minX, y: bannerY, width: box.width * (patrol ? 1 : 0.84), height: box.height * 0.33)
        context.setFillColor((patrol || clean ? blue : yellow).cgColor)
        context.fill(banner)
        if clean {
            ("★★★★★" as NSString).draw(in: CGRect(x: box.minX, y: box.minY - box.height * 0.02, width: box.width * 0.45, height: box.height * 0.16),
                withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.12), .foregroundColor: yellow, .paragraphStyle: paragraph])
        }
        let titleWidth = banner.width * (patrol ? 0.72 : 0.55)
        (headline as NSString).draw(in: CGRect(x: banner.minX + banner.width * 0.04, y: banner.minY + banner.height * 0.12, width: titleWidth, height: banner.height * 0.78),
            withAttributes: [.font: UIFont.systemFont(ofSize: banner.height * 0.46, weight: .bold), .foregroundColor: patrol ? yellow : clean ? UIColor.white : UIColor.black, .paragraphStyle: paragraph])
        if !patrol {
            (content.time as NSString).draw(in: CGRect(x: banner.minX + banner.width * 0.59, y: banner.minY + banner.height * 0.05, width: banner.width * 0.39, height: banner.height * 0.88),
                withAttributes: [.font: fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: banner.height * 0.62, weight: .medium), sample: "88:88", width: banner.width * 0.39), .foregroundColor: clean ? UIColor.white : blue, .paragraphStyle: paragraph])
        }
        let bodyY = banner.maxY + box.height * 0.08
        context.setFillColor((clean ? blue : yellow).cgColor)
        context.fill(CGRect(x: box.minX, y: bodyY, width: max(1, box.width * 0.008), height: box.maxY - bodyY))
        let lines = patrol ? [content.time + "  " + content.date, content.address ?? ""] : [content.date, content.address ?? ""]
        for index in lines.indices {
            (lines[index] as NSString).draw(in: CGRect(x: box.minX + box.width * 0.04, y: bodyY + CGFloat(index) * box.height * 0.20, width: box.width * 0.95, height: box.height * 0.20),
                withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.13, weight: .medium), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        return true
    }
    static func fixedMapRect(in size: CGSize) -> CGRect {
        let box = workReportRect(in: size)
        let side = min(box.height * 0.9, box.width * 0.32)
        return CGRect(x: box.maxX - side, y: box.midY - side / 2, width: side, height: side)
    }

    static func drawMapTemplate(snapshot: StampSnapshot, map: UIImage?, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        let mapRect = fixedMapRect(in: size)
        context.saveGState()
        defer { context.restoreGState() }
        if snapshot.mapEnabled, let map {
            map.draw(in: mapRect)
            let marker = mapRect.width * 0.12
            context.setFillColor(UIColor.systemBlue.cgColor)
            context.fillEllipse(in: CGRect(x: mapRect.midX - marker / 2, y: mapRect.midY - marker / 2, width: marker, height: marker))
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(max(1, marker * 0.12))
            context.strokeEllipse(in: CGRect(x: mapRect.midX - marker / 2, y: mapRect.midY - marker / 2, width: marker, height: marker))
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let column = box.width * 0.64
        if snapshot.layout.template == .visit || snapshot.layout.template == .delivery {
            let delivery = snapshot.layout.template == .delivery
            let top = CGRect(x: box.minX, y: box.minY, width: column, height: box.height * 0.36)
            context.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            context.fill(top)
            if delivery {
                context.setStrokeColor(UIColor.black.cgColor)
                context.setLineWidth(max(1, top.width * 0.008))
                context.stroke(top.insetBy(dx: top.width * 0.004, dy: top.width * 0.004))
                let lines = [content.customFields["Veículo"] ?? "", content.customFields["Encomenda"] ?? ""]
                let symbols = ["truck.box.fill", "shippingbox.fill"]
                for index in lines.indices {
                    let rowY = top.minY + CGFloat(index) * top.height * 0.5
                    let side = top.height * 0.32
                    let tint: UIColor = index == 0 ? .systemOrange : .systemBrown
                    if let icon = UIImage(systemName: symbols[index])?.withTintColor(tint, renderingMode: .alwaysOriginal) {
                        icon.draw(in: CGRect(x: top.minX + top.width * 0.035, y: rowY + top.height * 0.08, width: side, height: side))
                    }
                    (lines[index] as NSString).draw(in: CGRect(x: top.minX + top.width * 0.05 + side, y: rowY, width: top.width * 0.9 - side, height: top.height * 0.48),
                        withAttributes: [.font: UIFont.systemFont(ofSize: top.height * 0.30, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
                }
            } else {
                context.setFillColor(UIColor.systemYellow.cgColor)
                context.fill(CGRect(x: top.minX, y: top.minY, width: top.width * 0.45, height: top.height))
                let title = content.customFields["Título"] ?? "Visita"
                (title as NSString).draw(in: CGRect(x: top.minX + top.width * 0.03, y: top.minY + top.height * 0.10, width: top.width * 0.40, height: top.height * 0.8),
                    withAttributes: [.font: UIFont.systemFont(ofSize: top.height * 0.52, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
                (content.time as NSString).draw(in: CGRect(x: top.minX + top.width * 0.48, y: top.minY + top.height * 0.08, width: top.width * 0.5, height: top.height * 0.85),
                    withAttributes: [.font: fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: top.height * 0.60, weight: .bold), sample: "88:88", width: top.width * 0.5), .foregroundColor: UIColor.systemBlue, .paragraphStyle: paragraph])
            }
            let lines = delivery ? [content.time + "  " + content.date, content.address ?? ""] : [content.date, content.address ?? "", content.coordinate ?? ""]
            for index in lines.indices {
                let font = !delivery && index == 2
                    ? fittedFixedFont(UIFont.systemFont(ofSize: box.height * 0.12, weight: .medium), sample: "88.88888°S, 188.88888°O", width: column * 0.94)
                    : UIFont.systemFont(ofSize: box.height * 0.12, weight: .medium)
                (lines[index] as NSString).draw(in: CGRect(x: box.minX + column * 0.03, y: top.maxY + box.height * (0.04 + CGFloat(index) * 0.19), width: column * 0.94, height: box.height * 0.18),
                    withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
            }
            return true
        }
        (content.time as NSString).draw(in: CGRect(x: box.minX, y: box.minY, width: column * 0.65, height: box.height * 0.52),
            withAttributes: [.font: fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: box.height * 0.40, weight: .medium), sample: "88:88", width: column * 0.65), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        context.setFillColor(UIColor.systemYellow.cgColor)
        context.fill(CGRect(x: box.minX + column * 0.68, y: box.minY + box.height * 0.05, width: max(1, box.width * 0.008), height: box.height * 0.40))
        (content.date as NSString).draw(in: CGRect(x: box.minX + column * 0.72, y: box.minY + box.height * 0.14, width: column * 0.28, height: box.height * 0.23),
            withAttributes: [.font: fittedFixedFont(UIFont.systemFont(ofSize: box.height * 0.12, weight: .semibold), sample: "88/88/8888", width: column * 0.28), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        for (index, text) in [content.address ?? "", content.coordinate ?? ""].enumerated() {
            let font = index == 1
                ? fittedFixedFont(UIFont.systemFont(ofSize: box.height * 0.12, weight: .medium), sample: "88.88888°S, 188.88888°O", width: column)
                : UIFont.systemFont(ofSize: box.height * 0.12, weight: .medium)
            (text as NSString).draw(in: CGRect(x: box.minX, y: box.minY + box.height * (0.57 + CGFloat(index) * 0.20), width: column, height: box.height * 0.18),
                withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        return true
    }
    static func drawTimeOrCustom(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        guard min(size.width, size.height) >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        context.saveGState()
        defer { context.restoreGState() }
        let yellow = UIColor(red: 1, green: 0.73, blue: 0.13, alpha: 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        func text(_ value: String, _ rect: CGRect, _ font: UIFont) {
            (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        if snapshot.layout.template == .timeLocation {
            text(content.time, CGRect(x: box.minX, y: box.minY, width: box.width * 0.57, height: box.height * 0.59),
                 fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: box.height * 0.52, weight: .medium), sample: "88:88", width: box.width * 0.57))
            context.setFillColor(yellow.cgColor)
            context.fill(CGRect(x: box.minX + box.width * 0.58, y: box.minY + box.height * 0.04, width: max(1, box.width * 0.008), height: box.height * 0.50))
            let dayFont = fittedFixedFont(UIFont.systemFont(ofSize: box.height * 0.16, weight: .semibold), sample: "88 set.", width: box.width * 0.37)
            text(content.dayMonth, CGRect(x: box.minX + box.width * 0.62, y: box.minY + box.height * 0.06, width: box.width * 0.37, height: box.height * 0.22), dayFont)
            text(content.year, CGRect(x: box.minX + box.width * 0.62, y: box.minY + box.height * 0.30, width: box.width * 0.37, height: box.height * 0.22), dayFont)
            text(content.address ?? "", CGRect(x: box.minX, y: box.minY + box.height * 0.67, width: box.width, height: box.height * 0.26),
                 UIFont.systemFont(ofSize: box.height * 0.16, weight: .semibold))
        } else {
            text(content.customFields["Título"] ?? "Seu Título", CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height * 0.26),
                 UIFont.systemFont(ofSize: box.height * 0.17, weight: .bold))
            context.setFillColor(yellow.cgColor)
            context.fill(CGRect(x: box.minX, y: box.minY + box.height * 0.3, width: max(1, box.width * 0.008), height: box.height * 0.68))
            let lines = [content.date + " " + content.time, content.address ?? "", content.coordinate ?? ""]
            for index in lines.indices {
                text(lines[index], CGRect(x: box.minX + box.width * 0.04, y: box.minY + box.height * (0.31 + CGFloat(index) * 0.21), width: box.width * 0.95, height: box.height * 0.20),
                     UIFont.systemFont(ofSize: box.height * 0.13, weight: .medium))
            }
        }
        return true
    }
    static func drawLocationWeather(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        let unit = min(size.width, size.height)
        guard unit >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(UIColor(white: 0.13, alpha: 0.84).cgColor)
        context.fill(box)
        context.setFillColor(UIColor(red: 1, green: 0.73, blue: 0.13, alpha: 1).cgColor)
        context.fill(CGRect(x: box.minX, y: box.maxY - box.height * 0.027, width: box.width, height: box.height * 0.027))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let inset = box.width * 0.04
        let available = box.width - inset * 2
        let addressParts = (content.address ?? "").split(separator: ",", maxSplits: 1).map(String.init)
        let location = addressParts.first ?? (snapshot.gpsEnabled ? "Localização indisponível" : "Localização desativada")
        let detail = addressParts.count > 1 ? addressParts[1].trimmingCharacters(in: .whitespaces) : ""
        let lines = [location, detail, content.coordinate ?? "", content.date + " " + content.time]
        for index in lines.indices {
            let y = box.minY + box.height * (0.08 + CGFloat(index) * 0.21)
            let width = index >= 2 ? available * 0.7 : available
            let base = UIFont.systemFont(ofSize: box.height * (index == 0 ? 0.15 : 0.11), weight: index == 0 ? .medium : .regular)
            let font = index == 2 ? fittedFixedFont(base, sample: "88.88888°S, 188.88888°O", width: width) : base
            (lines[index] as NSString).draw(in: CGRect(x: box.minX + inset, y: y, width: width, height: box.height * 0.2),
                withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        if let heading = snapshot.heading {
            let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            if degrees >= 0 {
                let right = NSMutableParagraphStyle(); right.alignment = .right
                (String(format: "%.0f°", degrees) as NSString).draw(in: CGRect(x: box.midX, y: box.minY + box.height * 0.50, width: box.width * 0.46, height: box.height * 0.2),
                    withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.11), .foregroundColor: UIColor.white, .paragraphStyle: right])
            }
        }
        if let temperature = snapshot.forecast?.temperatureC {
            let text = String(format: "%.0f °C", temperature) as NSString
            let right = NSMutableParagraphStyle(); right.alignment = .right
            text.draw(in: CGRect(x: box.midX, y: box.minY + box.height * 0.72, width: box.width * 0.46, height: box.height * 0.2),
                withAttributes: [.font: UIFont.systemFont(ofSize: box.height * 0.11), .foregroundColor: UIColor.white, .paragraphStyle: right])
        }
        return true
    }
    static func drawSpreadsheet(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        let unit = min(size.width, size.height)
        guard unit >= 40 else { return false }
        let box = workReportRect(in: size)
        guard CGRect(origin: .zero, size: size).contains(box) else { return false }
        let content = snapshot.templateContent(address: address)
        let green = UIColor(red: 0.38, green: 0.87, blue: 0.66, alpha: 1)
        let header = box.height * 0.35
        let separator = box.width * 0.28
        let rowHeight = (box.height - header) / 2
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(UIColor(white: 0.18, alpha: 0.76).cgColor)
        context.fill(box)
        context.setStrokeColor(green.cgColor)
        context.setLineWidth(max(1, box.width * 0.003))
        context.stroke(box)
        context.move(to: CGPoint(x: box.minX, y: box.minY + header))
        context.addLine(to: CGPoint(x: box.maxX, y: box.minY + header))
        context.move(to: CGPoint(x: box.minX, y: box.minY + header + rowHeight))
        context.addLine(to: CGPoint(x: box.maxX, y: box.minY + header + rowHeight))
        context.move(to: CGPoint(x: box.minX + separator, y: box.minY + header))
        context.addLine(to: CGPoint(x: box.minX + separator, y: box.maxY))
        context.strokePath()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let inset = box.width * 0.025
        let title = content.customFields["Título"] ?? "Registro de Trabalho"
        (title as NSString).draw(in: CGRect(x: box.minX + inset, y: box.minY + header * 0.16, width: box.width - inset * 2, height: header * 0.75),
            withAttributes: [.font: condensedStampFont(size: header * 0.52, bold: true), .foregroundColor: green, .paragraphStyle: paragraph])
        let labels = ["Hora", "Endereço"]
        let values = [content.date + " " + content.time, content.address ?? ""]
        for index in 0..<2 {
            let y = box.minY + header + CGFloat(index) * rowHeight + rowHeight * 0.18
            (labels[index] as NSString).draw(in: CGRect(x: box.minX + inset, y: y, width: separator - inset * 2, height: rowHeight * 0.8),
                withAttributes: [.font: condensedStampFont(size: rowHeight * 0.42, bold: true), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
            (values[index] as NSString).draw(in: CGRect(x: box.minX + separator + inset, y: y, width: box.width - separator - inset * 2, height: rowHeight * 0.8),
                withAttributes: [.font: condensedStampFont(size: rowHeight * 0.40), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        }
        return true
    }
    static func workReportRect(in size: CGSize) -> CGRect {
        let unit = min(size.width, size.height)
        let width = unit * 0.78
        let height = width * 0.49
        let margin = unit * 0.035
        return CGRect(x: margin, y: size.height - margin - height, width: width, height: height)
    }
    /// Fixed-proportion work report, shared by photo and video rendering.
    static func drawWorkReport(snapshot: StampSnapshot, address: String?, size: CGSize, context: CGContext) -> Bool {
        let unit = min(size.width, size.height)
        guard unit >= 40 else { return false }
        let width = unit * 0.78
        let height = width * 0.49
        let margin = unit * 0.035
        guard size.width >= width + margin * 2, size.height >= height + margin * 2 else { return false }
        let box = workReportRect(in: size)
        let content = snapshot.templateContent(address: address)
        let headerHeight = height * 0.31
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(UIColor(red: 0.84, green: 0.52, blue: 0.18, alpha: 0.95).cgColor)
        context.fill(CGRect(x: box.minX, y: box.minY, width: width, height: headerHeight))
        context.setFillColor(UIColor(white: 0.82, alpha: 0.94).cgColor)
        context.fill(CGRect(x: box.minX, y: box.minY + headerHeight, width: width, height: height - headerHeight))
        let padding = width * 0.035
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleFont = condensedStampFont(size: height * 0.16, bold: true)
        ("Relatório de trabalho" as NSString).draw(in: CGRect(x: box.minX + padding, y: box.minY + height * 0.055, width: width - padding * 2, height: headerHeight * 0.8),
            withAttributes: [.font: titleFont, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
        let rowHeight = (height - headerHeight) / 3
        let labels = ["Projeto", "Inspeção", "Endereço"]
        let values = [content.customFields["Projeto"] ?? "", content.customFields["Inspeção"] ?? "", content.address ?? ""]
        let font = condensedStampFont(size: height * 0.105)
        let bold = condensedStampFont(size: height * 0.105, bold: true)
        for index in 0..<3 {
            let y = box.minY + headerHeight + CGFloat(index) * rowHeight + rowHeight * 0.2
            (labels[index] as NSString).draw(in: CGRect(x: box.minX + padding, y: y, width: width * 0.28, height: rowHeight * 0.8),
                withAttributes: [.font: font, .foregroundColor: UIColor.darkGray, .paragraphStyle: paragraph])
            (values[index] as NSString).draw(in: CGRect(x: box.minX + width * 0.30, y: y, width: width * 0.66, height: rowHeight * 0.8),
                withAttributes: [.font: bold, .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        }
        return true
    }
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
            if snapshot.layout.template == .workReport {
                fits = drawWorkReport(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .spreadsheet {
                fits = drawSpreadsheet(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .locationWeather {
                fits = drawLocationWeather(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .timeLocation || snapshot.layout.template == .custom {
                fits = drawTimeOrCustom(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if [.map, .visit, .delivery].contains(snapshot.layout.template) {
                fits = drawMapTemplate(snapshot: snapshot, map: map, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .largeMap {
                fits = drawLargeMap(snapshot: snapshot, map: map, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .patrol {
                fits = drawPatrol(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if [.clean, .checkIn].contains(snapshot.layout.template) {
                fits = drawBannerTemplate(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .completed || snapshot.layout.template == .deliveryProof {
                fits = drawProofTemplate(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .inspection {
                fits = drawInspection(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .portrait {
                fits = drawPortrait(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .shopee {
                fits = drawShippingTemplate(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
            if snapshot.layout.template == .construction {
                fits = drawConstruction(snapshot: snapshot, address: address, size: size, context: context.cgContext)
                return
            }
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
