import Foundation
import ImageIO
import UIKit

enum ProfileLogoStore {
    static func save(_ data: Data) throws -> String {
        guard !data.isEmpty, data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary),
              let png = UIImage(cgImage: image).pngData() else { throw LogoError.invalid }
        let directory = try directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let name = UUID().uuidString + ".png"
        try png.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }

    static func load(_ name: String) -> UIImage? {
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
              let directory = try? directory() else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }

    private static func directory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ProfileLogos", isDirectory: true)
    }

    enum LogoError: LocalizedError {
        case invalid
        var errorDescription: String? { "Não foi possível usar essa imagem. Escolha uma imagem de até 20 MB." }
    }
}
