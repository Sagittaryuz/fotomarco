import CoreImage
import ImageIO
import UniformTypeIdentifiers
import UIKit

enum PhotoAdjustment: String, CaseIterable, Hashable {
    case exposure = "Exposição", brilliance = "Luminosidade", highlights = "Altas-luzes"
    case shadows = "Sombras", contrast = "Contraste", brightness = "Brilho", blackPoint = "Ponto preto"
    case saturation = "Saturação", vibrance = "Vivacidade", warmth = "Temperatura", tint = "Matiz"
    case sharpness = "Nitidez", definition = "Definição", noise = "Redução de ruído", vignette = "Vinheta"
}

enum PhotoEditFilter: String, CaseIterable {
    case original = "Original", vivid = "Vívido", vividWarm = "Vívido quente", vividCool = "Vívido frio"
    case dramatic = "Dramático", dramaticWarm = "Dramático quente", dramaticCool = "Dramático frio"
    case mono = "Mono", tonal = "Tonal", noir = "Noir"
}

enum PhotoCropRatio: String, CaseIterable {
    case free = "Livre", square = "1:1", fourThree = "4:3", threeTwo = "3:2", wide = "16:9", portrait = "9:16"

    var value: CGFloat? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3
        case .threeTwo: 3.0 / 2
        case .wide: 16.0 / 9
        case .portrait: 9.0 / 16
        }
    }
}

enum PhotoInk: String, CaseIterable {
    case white = "Branco", yellow = "Amarelo", red = "Vermelho", black = "Preto"

    var color: UIColor {
        switch self {
        case .white: .white
        case .yellow: .systemYellow
        case .red: .systemRed
        case .black: .black
        }
    }
}

struct PhotoStroke: Equatable {
    let ink: PhotoInk
    let points: [CGPoint]

    func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        func point(_ value: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + value.x * rect.width, y: rect.minY + value.y * rect.height)
        }
        path.move(to: point(first))
        for value in points.dropFirst() { path.addLine(to: point(value)) }
        if points.count == 1 { path.addLine(to: point(first).applying(.init(translationX: 0.2, y: 0))) }
        return path
    }
}

struct PhotoEditRecipe: Equatable {
    var automatic = false
    var adjustments: [PhotoAdjustment: Double] = [:]
    var filter: PhotoEditFilter = .original
    var strength = 1.0
    var turns = 0
    var flipped = false
    var angle = 0.0
    var vertical = 0.0
    var horizontal = 0.0
    var crop: PhotoCropRatio = .free
    var cropScale = 1.0
    var cropCenter = CGPoint(x: 0.5, y: 0.5)
    var strokes: [PhotoStroke] = []

    subscript(_ adjustment: PhotoAdjustment) -> Double {
        get { adjustments[adjustment] ?? 0 }
        set { adjustments[adjustment] = abs(newValue) < 0.005 ? nil : newValue }
    }
}

enum PhotoEditRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func previewSource(_ url: URL, maximumPixels: Int = 1250) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixels
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return bitmap
    }

    static func preview(_ source: CGImage, recipe: PhotoEditRecipe) -> CGImage? {
        let output = render(CIImage(cgImage: source), recipe: recipe)
        return context.createCGImage(output, from: output.extent)
    }

    static func export(_ url: URL, recipe: PhotoEditRecipe) throws -> Data {
        guard let source = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              source.extent.width >= 1, source.extent.height >= 1,
              source.extent.width * source.extent.height <= 85_000_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let output = render(source, recipe: recipe)
        guard let cg = context.createCGImage(output, from: output.extent) else { throw CocoaError(.fileWriteUnknown) }
        let original = UIImage(cgImage: cg)
        let result: CGImage
        if recipe.strokes.isEmpty { result = cg }
        else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let annotated = UIGraphicsImageRenderer(size: original.size, format: format).image { ctx in
                let box = CGRect(origin: .zero, size: original.size)
                original.draw(in: box)
                let drawing = ctx.cgContext
                drawing.setLineCap(.round)
                drawing.setLineJoin(.round)
                drawing.setLineWidth(max(1, min(box.width, box.height) * 0.012))
                for stroke in recipe.strokes {
                    drawing.setStrokeColor(stroke.ink.color.cgColor)
                    drawing.addPath(stroke.path(in: box))
                    drawing.strokePath()
                }
            }
            guard let bitmap = annotated.cgImage else { throw CocoaError(.fileWriteUnknown) }
            result = bitmap
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.94]
        for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            if let value = source.properties[key as String] { properties[key as String] = value }
        }
        if let exif = source.properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            properties[kCGImagePropertyExifDictionary as String] = exif.filter {
                [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifOffsetTimeOriginal].map { $0 as String }.contains($0.key)
            }
        }
        CGImageDestinationAddImage(destination, result, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    private static func render(_ source: CIImage, recipe r: PhotoEditRecipe) -> CIImage {
        let originalExtent = source.extent
        var image = source
        if r.automatic {
            for filter in source.autoAdjustmentFilters(options: [.enhance: true, .redEye: false, .crop: false, .level: false]) {
                filter.setValue(image, forKey: kCIInputImageKey)
                image = filter.outputImage ?? image
            }
        }
        image = applyFilter(r.filter, strength: r.strength, to: image)
        if r[.exposure] != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: r[.exposure] * 2])
        }
        if r[.brilliance] != 0 || r[.highlights] != 0 || r[.shadows] != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 + r[.highlights] * 0.70 - r[.brilliance] * 0.25,
                "inputShadowAmount": r[.shadows] * 0.80 + r[.brilliance] * 0.40
            ])
        }
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: r[.brightness] * 0.22, kCIInputContrastKey: 1 + r[.contrast] * 0.60,
            kCIInputSaturationKey: 1 + r[.saturation]
        ])
        if r[.blackPoint] != 0 {
            let shift = r[.blackPoint] * 0.24
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1 + shift, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 + shift, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 + shift, w: 0),
                "inputBiasVector": CIVector(x: -shift, y: -shift, z: -shift, w: 0)
            ])
        }
        if r[.vibrance] != 0 {
            image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": r[.vibrance]])
        }
        if r[.warmth] != 0 || r[.tint] != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 - r[.warmth] * 2300, y: r[.tint] * 95)
            ])
        }
        if r[.noise] > 0 {
            image = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": r[.noise] * 0.075, "inputSharpness": 0.4])
        }
        if r[.sharpness] > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: r[.sharpness] * 1.2])
        }
        if r[.definition] > 0 {
            image = image.applyingFilter("CIUnsharpMask", parameters: [kCIInputIntensityKey: r[.definition], kCIInputRadiusKey: 5])
        }
        if r[.vignette] > 0 {
            image = image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: r[.vignette] * 2.2, kCIInputRadiusKey: 1.2])
        }
        image = image.cropped(to: originalExtent)
        for _ in 0..<r.turns { image = image.oriented(.right) }
        if r.flipped { image = image.oriented(.upMirrored) }
        image = straighten(image, degrees: r.angle)
        image = perspective(image, vertical: r.vertical, horizontal: r.horizontal)
        var box = image.extent
        if let ratio = r.crop.value {
            if box.width / box.height > ratio { box.size.width = box.height * ratio }
            else { box.size.height = box.width / ratio }
        }
        box.size.width *= r.cropScale
        box.size.height *= r.cropScale
        box.origin.x = image.extent.minX + (image.extent.width - box.width) * r.cropCenter.x
        box.origin.y = image.extent.minY + (image.extent.height - box.height) * (1 - r.cropCenter.y)
        let pixels = CGRect(x: box.minX.rounded(), y: box.minY.rounded(),
                            width: max(1, box.width.rounded()), height: max(1, box.height.rounded()))
        return image.cropped(to: pixels.intersection(image.extent))
    }

    private static func applyFilter(_ filter: PhotoEditFilter, strength: Double, to image: CIImage) -> CIImage {
        guard filter != .original, strength > 0 else { return image }
        let output: CIImage
        switch filter {
        case .original: output = image
        case .vivid, .vividWarm, .vividCool:
            output = image.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.7])
        case .dramatic, .dramaticWarm, .dramaticCool:
            output = image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.32, kCIInputSaturationKey: 0.65])
        case .mono: output = image.applyingFilter("CIPhotoEffectMono")
        case .tonal: output = image.applyingFilter("CIPhotoEffectTonal")
        case .noir: output = image.applyingFilter("CIPhotoEffectNoir")
        }
        var tinted = output
        if [.vividWarm, .dramaticWarm, .vividCool, .dramaticCool].contains(filter) {
            let warm = filter == .vividWarm || filter == .dramaticWarm
            tinted = output.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: warm ? 4700 : 8200, y: 0)
            ])
        }
        guard strength < 1 else { return tinted }
        let mask = CIImage(color: CIColor(red: strength, green: strength, blue: strength)).cropped(to: image.extent)
        return tinted.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
    }

    private static func straighten(_ image: CIImage, degrees: Double) -> CIImage {
        guard degrees != 0 else { return image }
        let box = image.extent
        let angle = degrees * .pi / 180
        let ratio = box.width / box.height
        let scale = abs(cos(angle)) + abs(sin(angle)) * max(ratio, 1 / ratio)
        let transform = CGAffineTransform(translationX: box.midX, y: box.midY).scaledBy(x: scale, y: scale)
            .rotated(by: angle).translatedBy(x: -box.midX, y: -box.midY)
        return image.transformed(by: transform).cropped(to: box)
    }

    private static func perspective(_ image: CIImage, vertical: Double, horizontal: Double) -> CIImage {
        guard vertical != 0 || horizontal != 0 else { return image }
        let b = image.extent
        let top = max(0, vertical) * b.width * 0.15
        let bottom = max(0, -vertical) * b.width * 0.15
        let left = max(0, horizontal) * b.height * 0.15
        let right = max(0, -horizontal) * b.height * 0.15
        return image.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: b.minX + top, y: b.maxY - left),
            "inputTopRight": CIVector(x: b.maxX - top, y: b.maxY - right),
            "inputBottomLeft": CIVector(x: b.minX + bottom, y: b.minY + left),
            "inputBottomRight": CIVector(x: b.maxX - bottom, y: b.minY + right)
        ]).cropped(to: b.insetBy(dx: max(top, bottom) * 1.15, dy: max(left, right) * 1.15))
    }
}
