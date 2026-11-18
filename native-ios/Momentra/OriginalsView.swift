import SwiftUI
import Photos
import ImageIO
import QuickLook

private struct OriginalFile: Identifiable {
    let url: URL
    let isVideo: Bool
    let isProcessed: Bool
    let date: Date?
    var id: URL { url }
}

private enum OriginalStore {
    static func files() throws -> [OriginalFile] {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        return try [("Originals", false, false), ("Processed", false, true), ("Videos", true, false), ("ProcessedVideos", true, true)].flatMap { folder, isVideo, isProcessed -> [OriginalFile] in
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]).compactMap { url in
                let info = try url.resourceValues(forKeys: Set(keys))
                guard info.isRegularFile == true else { return nil }
                return OriginalFile(url: url, isVideo: isVideo, isProcessed: isProcessed, date: info.contentModificationDate)
            }
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

struct OriginalsView: View {
    @ObservedObject var googlePhotos: GooglePhotosManager
    @ObservedObject var stampProfiles: StampProfilesStore
    @Environment(\.dismiss) private var dismiss
    @State private var files: [OriginalFile] = []
    @State private var message: String?
    @State private var isSaving = false
    @State private var photoForGoogle: URL?
    @State private var showPhotoConsent = false
    @State private var gallerySection = 0
    @State private var profileLookup = PhotoProfileLookup()
    @State private var reloadToken = UUID()
    @State private var captureColumns = 3
    @State private var selectedCapture: URL?
    @StateObject private var picker = GooglePickerFlow()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Galeria", selection: $gallerySection) {
                    Text("Capturas").tag(0)
                    Text("Celular").tag(1)
                    Text("Nuvem").tag(2)
                }.pickerStyle(.segmented).padding()
                GalleryStorageSummary(cloud: gallerySection == 2)
                if gallerySection == 0 {
                    captures
                } else if gallerySection == 1 {
                    DevicePhotoGallery(profileLookup: profileLookup, stampProfiles: stampProfiles)
                } else {
                    CloudPhotoGallery(googlePhotos: googlePhotos, picker: picker, profileLookup: profileLookup, stampProfiles: stampProfiles)
                }
            }
            .navigationTitle("Galeria")
            .toolbar { Button("Concluído") { picker.cancel(); dismiss() } }
            .interactiveDismissDisabled(picker.busy || picker.waitingForSelection)
            .onAppear { reload() }
            .quickLookPreview($selectedCapture)
            .onChange(of: gallerySection) { previous, section in
                if previous == 2 && section != 2 { picker.cancel() }
                reload()
            }
            .confirmationDialog("Envie somente uma foto pessoal. O arquivo local será mantido e a foto será enviada à conta Google conectada.", isPresented: $showPhotoConsent, titleVisibility: .visible) {
                Button("Confirmo uso pessoal e envio") {
                    if let url = photoForGoogle { googlePhotos.sendProcessedPhoto(url) }
                    photoForGoogle = nil
                }
                Button("Cancelar", role: .cancel) { photoForGoogle = nil }
            }
            .onChange(of: googlePhotos.message) { _, value in
                if let value { message = value; googlePhotos.message = nil; reload() }
            }
            .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func resolved(_ tag: CaptureProfileTag?) -> CaptureProfileTag? {
        guard let tag else { return nil }
        if let profile = stampProfiles.profiles.first(where: { $0.id == tag.id }) {
            return CaptureProfileTag(id: tag.id, name: profile.name)
        }
        return tag
    }

    private var captureGroups: [GalleryGroup<OriginalFile>] {
        GalleryGrouping.groups(files, date: { item in
            guard let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent) else { return item.date }
            return profileLookup.dates[id] ?? item.date
        }, profile: { item in
            guard let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent) else { return nil }
            return resolved(profileLookup.captures[id])
        })
    }

    private var captures: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if files.isEmpty {
                    ContentUnavailableView("Nenhuma captura disponível", systemImage: "photo")
                }
                ForEach(captureGroups) { group in
                    Text(group.title).font(.headline).padding(.horizontal, 12)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: captureColumns), spacing: 3) {
                        ForEach(group.items) { item in
                            ZStack(alignment: .bottomTrailing) {
                                Button { selectedCapture = item.url } label: {
                                    Thumbnail(url: item.url, isVideo: item.isVideo)
                                }.buttonStyle(.plain).accessibilityLabel("Abrir captura")
                                Menu {
                                    ShareLink(item: item.url) { Label("Compartilhar", systemImage: "square.and.arrow.up") }
                                    Button { save(item) } label: { Label("Salvar no Fotos", systemImage: "square.and.arrow.down") }
                                        .disabled(isSaving)
                                    if googlePhotos.configured && item.isProcessed && !item.isVideo {
                                        Button { photoForGoogle = item.url; showPhotoConsent = true } label: {
                                            Label("Enviar ao Google Fotos", systemImage: "cloud.and.arrow.up")
                                        }.disabled(googlePhotos.busy)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle.fill")
                                        .font(.title3).foregroundStyle(.white).shadow(radius: 2).padding(6)
                                }.accessibilityLabel("Opções da captura")
                            }
                        }
                    }
                }
            }
        }
        .simultaneousGesture(MagnifyGesture().onEnded { value in
            withAnimation(.easeInOut(duration: 0.2)) {
                captureColumns = GalleryZoom.next(columns: captureColumns, magnification: value.magnification)
            }
        })
    }

    private func reload() {
        let token = UUID()
        reloadToken = token
        Task {
            let result = await Task.detached(priority: .utility) { () -> (PhotoProfileLookup, [OriginalFile]?) in
                (PhotoProfileIndex.load(), try? OriginalStore.files())
            }.value
            guard reloadToken == token else { return }
            profileLookup = result.0
            if let loaded = result.1 { files = loaded }
            else { message = "Não foi possível abrir as capturas guardadas." }
        }
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
                    message = success ? "Arquivo salvo no Fotos." : "Não foi possível salvar. O arquivo continua no aplicativo."
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
        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit).clipped()
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
