import CoreLocation
import UIKit

struct StampSnapshot {
    let capturedAt: Date
    let gpsEnabled: Bool
    let location: CLLocation?
    let heading: CLHeading?

    init(capturedAt: Date, gpsEnabled: Bool, location: CLLocation?, heading: CLHeading?) {
        self.capturedAt = capturedAt
        self.gpsEnabled = gpsEnabled
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
    static func render(_ data: Data, snapshot: StampSnapshot) -> Data? {
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
            let text = snapshot.lines.joined(separator: "\n") as NSString
            let textWidth = size.width - margin * 4
            let measured = text.boundingRect(with: CGSize(width: textWidth, height: size.height * 0.6), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            let height = ceil(measured.height) + margin * 2
            let box = CGRect(x: margin, y: size.height - margin - height, width: size.width - margin * 2, height: height)
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.65).cgColor)
            context.cgContext.fill(box)
            text.draw(in: box.insetBy(dx: margin, dy: margin), withAttributes: attrs)
        }
        return result.jpegData(compressionQuality: 0.95)
    }
}
