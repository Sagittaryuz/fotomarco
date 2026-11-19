import Photos
import SwiftUI

struct GalleryBenchmarkFixture: ViewModifier {
    @State private var result: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if let result {
                    Text(result).font(.caption2).padding(2)
                        .accessibilityIdentifier("gallery-benchmark-fixtures")
                }
            }
            .task {
                guard result == nil, ProcessInfo.processInfo.arguments.contains("-seedGalleryBenchmark") else { return }
                result = await seed()
            }
    }

    private func seed() async -> String {
        let access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard access == .authorized else { return "Fotos indisponível: \(access.rawValue)" }
        let images = (1...24).compactMap { index in
            let size = CGSize(width: CGFloat(256 + index), height: 190)
            return UIGraphicsImageRenderer(size: size).image { context in
                UIColor(hue: CGFloat(index) / 24, saturation: 0.8, brightness: 0.8, alpha: 1).setFill()
                context.cgContext.fill(CGRect(origin: .zero, size: size))
            }.jpegData(compressionQuality: 0.85)
        }
        var ids: [String] = []
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for image in images {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: image, options: nil)
                    if let id = request.placeholderForCreatedAsset?.localIdentifier { ids.append(id) }
                }
            }
            let verified = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count
            return "\(verified) fotos pessoais de teste"
        } catch {
            return "Falha ao inserir fotos de teste"
        }
    }
}
