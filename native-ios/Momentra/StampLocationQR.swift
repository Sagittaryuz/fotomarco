import CoreImage
import CoreLocation
import UIKit

/// QR codes contain only the coordinates captured in the photograph.
enum StampLocationQR {
    private static let context = CIContext(options: nil)
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    static func url(for coordinate: CLLocationCoordinate2D) -> URL? {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let locale = Locale(identifier: "en_US_POSIX")
        let latitude = String(format: "%.6f", locale: locale, coordinate.latitude)
        let longitude = String(format: "%.6f", locale: locale, coordinate.longitude)
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [URLQueryItem(name: "api", value: "1"),
                                  URLQueryItem(name: "query", value: "\(latitude),\(longitude)")]
        return components?.url
    }

    static func image(for coordinate: CLLocationCoordinate2D) -> UIImage? {
        guard let url = url(for: coordinate) else { return nil }
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let code = context.createCGImage(output, from: output.extent) else { return nil }
        // Four clear modules around the symbol preserve the QR quiet zone.
        let modules = code.width + 8
        let pixelsPerModule = max(1, 512 / modules)
        let side = modules * pixelsPerModule
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(side), height: CGFloat(side)), format: format).image { renderer in
            UIColor.white.setFill(); renderer.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
            renderer.cgContext.interpolationQuality = .none
            UIImage(cgImage: code).draw(in: CGRect(x: CGFloat(4 * pixelsPerModule), y: CGFloat(4 * pixelsPerModule),
                                                    width: CGFloat(code.width * pixelsPerModule), height: CGFloat(code.height * pixelsPerModule)))
        }
        cache.setObject(image, forKey: key)
        return image
    }

    static func rect(in size: CGSize, layout: StampLayout) -> CGRect {
        let unit = min(size.width, size.height)
        let margin = unit * 0.025
        let space = StampRenderer.availableSize(size: size, anchor: layout.locationQR, margin: margin)
        let side = min(space.width, space.height, unit * 0.32, unit * 0.18 * CGFloat(layout.locationQRSize))
        return StampRenderer.positionedRect(size: size, element: CGSize(width: side, height: side),
                                            centre: layout.locationQR, margin: margin)
    }
}
