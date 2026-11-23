import Foundation
import UIKit
import ImageIO

/// Transfers a copy of a profile. The personal profile and its local files remain untouched.
@MainActor
struct BusinessProfileTransfer {
    enum Failure: Error { case missingImage, imageTooLarge, invalidProfile, invalidAsset }
    private static let prefix = "business-asset:"
    let api: BusinessAPIClient

    func publish(_ personal: StampProfile, organizationID: String, token: String) async throws -> String {
        var profile = personal
        var uploaded: [String: String] = [:]
        func upload(_ name: String) async throws -> String {
            if name.isEmpty { return "" }
            if let existing = uploaded[name] { return existing }
            guard let image = ProfileLogoStore.load(name), let original = image.pngData() else { throw Failure.missingImage }
            let data = try Self.uploadImage(original)
            let asset = try await api.uploadAsset(organizationID: organizationID, mimeType: "image/png", imageData: data, token: token)
            let ref = Self.prefix + asset.assetId
            uploaded[name] = ref
            return ref
        }
        profile.logoName = try await upload(profile.logoName)
        for template in profile.layout.templateValues.keys.sorted() {
            for key in ["_image", "_image2", "_image3"] {
                if let name = profile.layout.templateValues[template]?[key], !name.isEmpty {
                    let reference = try await upload(name)
                    profile.layout.templateValues[template]?[key] = reference
                }
            }
        }
        let data = try JSONEncoder().encode(profile)
        guard let json = String(data: data, encoding: .utf8) else { throw Failure.invalidProfile }
        return try await api.publishProfile(organizationID: organizationID, layoutJSON: json, token: token).versionId
    }

    func fetch(organizationID: String, token: String) async throws -> StampProfile {
        let receipt = try await api.readProfile(organizationID: organizationID, token: token)
        guard receipt.organizationId == organizationID, let data = receipt.layoutJSON.data(using: .utf8),
              var profile = try? JSONDecoder().decode(StampProfile.self, from: data) else { throw Failure.invalidProfile }
        var saved: [String: String] = [:]
        func download(_ reference: String) async throws -> String {
            if reference.isEmpty { return "" }
            if let existing = saved[reference] { return existing }
            guard reference.hasPrefix(Self.prefix) else { throw Failure.invalidAsset }
            let id = String(reference.dropFirst(Self.prefix.count))
            let asset = try await api.readAsset(organizationID: organizationID, assetID: id, token: token)
            guard ["image/png", "image/jpeg"].contains(asset.mimeType), let bytes = Data(base64Encoded: asset.base64), bytes.count <= 262144 else { throw Failure.invalidAsset }
            let local = try ProfileLogoStore.save(bytes)
            saved[reference] = local
            return local
        }
        profile.logoName = try await download(profile.logoName)
        for template in profile.layout.templateValues.keys.sorted() {
            for key in ["_image", "_image2", "_image3"] {
                if let reference = profile.layout.templateValues[template]?[key], !reference.isEmpty {
                    let localName = try await download(reference)
                    profile.layout.templateValues[template]?[key] = localName
                }
            }
        }
        return profile
    }

    private static func uploadImage(_ original: Data) throws -> Data {
        if original.count <= 262144 { return original }
        guard let source = CGImageSourceCreateWithData(original as CFData, nil) else { throw Failure.missingImage }
        for size in [768, 512, 384, 256, 128] {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size
            ] as CFDictionary), let png = UIImage(cgImage: image).pngData() else { continue }
            if png.count <= 262144 { return png }
        }
        throw Failure.imageTooLarge
    }
}
