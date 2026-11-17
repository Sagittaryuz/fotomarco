import SwiftUI
import Photos
import ImageIO

private struct OriginalFile: Identifiable {
    let url: URL
    let isVideo: Bool
    let date: Date
    var id: URL { url }
}

private enum OriginalStore {
    static func files() throws -> [OriginalFile] {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        return try [("Originals", false), ("Videos", true)].flatMap { folder, isVideo -> [OriginalFile] in
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]).compactMap { url in
                let info = try url.resourceValues(forKeys: Set(keys))
                guard info.isRegularFile == true else { return nil }
                return OriginalFile(url: url, isVideo: isVideo, date: info.contentModificationDate ?? .distantPast)
            }
        }.sorted { $0.date > $1.date }
    }
}

struct OriginalsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var files: [OriginalFile] = []
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Cópias originais guardadas neste aplicativo. Compartilhe ou salve no Fotos antes de desinstalá-lo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if files.isEmpty {
                    Text("Nenhum original disponível.").foregroundStyle(.secondary)
                }
                ForEach(files) { item in
                    HStack(spacing: 12) {
                        Thumbnail(url: item.url, isVideo: item.isVideo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.isVideo ? "Vídeo original" : "Foto original").font(.headline)
                            Text(item.date, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            ShareLink(item: item.url) { Label("Compartilhar", systemImage: "square.and.arrow.up") }
                            Button { save(item) } label: { Label("Salvar no Fotos", systemImage: "square.and.arrow.down") }
                                .disabled(isSaving)
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44)
                        }.accessibilityLabel("Opções do original")
                    }
                }
            }
            .navigationTitle("Originais")
            .toolbar { Button("Concluído") { dismiss() } }
            .onAppear { reload() }
            .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func reload() {
        do { files = try OriginalStore.files() }
        catch { message = "Não foi possível abrir os originais guardados." }
    }

    private func save(_ item: OriginalFile) {
        guard !isSaving else { return }
        isSaving = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { isSaving = false; message = "Permita o acesso ao Fotos nos Ajustes do iPhone." }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: item.isVideo ? .video : .photo, fileURL: item.url, options: nil)
            }) { success, _ in
                DispatchQueue.main.async {
                    isSaving = false
                    message = success ? "Original salvo no Fotos." : "Não foi possível salvar. O original continua no aplicativo."
                }
            }
        }
    }
}

private struct Thumbnail: View {
    let url: URL
    let isVideo: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.2))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: isVideo ? "video.fill" : "photo").foregroundStyle(.secondary) }
        }
        .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            guard !isVideo else { return }
            let fileURL = url
            let thumbnail = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 160
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: image)
            }.value
            image = thumbnail
        }
    }
}
