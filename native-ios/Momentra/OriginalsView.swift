import SwiftUI
import Photos
import ImageIO
import AVKit

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
    @ObservedObject var stampProfiles: StampProfilesStore
    @Environment(\.dismiss) private var dismiss
    @State private var files: [OriginalFile] = []
    @State private var message: String?
    @State private var isSaving = false
    @State private var gallerySection = 0
    @State private var profileLookup = PhotoProfileLookup()
    @State private var reloadToken = UUID()
    @State private var captureColumns = 3
    @State private var selectedCapture: URL?
    @State private var selectingCaptures = false
    @State private var selectedCaptureIDs: Set<URL> = []
    @StateObject private var archiveAccounts = CloudArchiveAccounts.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Galeria", selection: $gallerySection) {
                    Text("Capturas").tag(0)
                    Text("Celular").tag(1)
                    Text("Nuvem").tag(2)
                }.pickerStyle(.segmented).padding()
                if gallerySection != 2 { GalleryStorageSummary(cloud: false) }
                if gallerySection == 0 {
                    captures
                } else if gallerySection == 1 {
                    DevicePhotoGallery(profileLookup: profileLookup, stampProfiles: stampProfiles)
                } else {
                    CloudArchiveGallery(accounts: archiveAccounts,
                                        profileLookup: profileLookup, stampProfiles: stampProfiles)
                }
            }
            .navigationTitle("Galeria")
            .toolbar { Button("Concluído") { dismiss() } }
            .onAppear { reload() }
            .sheet(isPresented: Binding(get: { selectedCapture != nil }, set: { if !$0 { selectedCapture = nil } })) {
                if let selectedCapture {
                    CapturePager(items: captureGroups.flatMap(\.items), initialURL: selectedCapture,
                                 message: $message, save: save)
                        .presentationDragIndicator(.hidden)
                }
            }
            .onChange(of: gallerySection) { _, _ in
                selectingCaptures = false; selectedCaptureIDs.removeAll()
                reload()
            }
            .alert("Momentra", isPresented: Binding(get: { selectedCapture == nil && message != nil },
                                                     set: { if !$0, selectedCapture == nil { message = nil } })) {
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
        VStack(spacing: 0) {
                if files.isEmpty {
                    ContentUnavailableView("Nenhuma captura disponível", systemImage: "photo")
                } else {
                    GalleryGrid(groups: captureGroups, selecting: $selectingCaptures, selected: $selectedCaptureIDs, columns: $captureColumns) { item in
                        ZStack(alignment: .bottomTrailing) {
                            Thumbnail(url: item.url, isVideo: item.isVideo)
                                .overlay(alignment: .topLeading) {
                                    if item.isVideo {
                                        Text(item.isProcessed ? "Com carimbo" : "Original")
                                            .font(.caption2.bold()).foregroundStyle(.white).padding(4)
                                            .background(.black.opacity(0.7), in: Capsule()).padding(4)
                                    }
                                }
                            Menu {
                                ShareLink(item: item.url) { Label("Compartilhar", systemImage: "square.and.arrow.up") }
                                Button { save(item) } label: { Label("Salvar no Fotos", systemImage: "square.and.arrow.down") }.disabled(isSaving)
                            } label: {
                                Image(systemName: "ellipsis.circle.fill").font(.title3).foregroundStyle(.white).shadow(radius: 2).padding(6)
                            }.accessibilityLabel("Opções da captura")
                        }
                    } open: { item in selectedCapture = item.url }
                }
                if selectingCaptures {
                    HStack {
                        Text("\(selectedCaptureIDs.count) selecionada(s)")
                        Spacer()
                        if !selectedCaptureIDs.isEmpty {
                            ShareLink(items: files.filter { selectedCaptureIDs.contains($0.url) }.map(\.url)) { Label("Compartilhar", systemImage: "square.and.arrow.up") }
                        }
                        Button("Selecionar todas") { selectedCaptureIDs = Set(files.map(\.id)) }
                    }.font(.footnote).padding()
                }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(selectingCaptures ? "Cancelar" : "Selecionar") {
                    selectingCaptures.toggle(); if !selectingCaptures { selectedCaptureIDs.removeAll() }
                }
            }
        }
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
            if let loaded = result.1 {
                files = loaded
                selectedCaptureIDs.formIntersection(Set(loaded.map(\.id)))
            }
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

private struct CapturePager: View {
    let items: [OriginalFile]
    let save: (OriginalFile) -> Void
    @Binding var message: String?
    @State private var selection: URL
    @Environment(\.dismiss) private var dismiss

    init(items: [OriginalFile], initialURL: URL, message: Binding<String?>, save: @escaping (OriginalFile) -> Void) {
        self.items = items
        self.save = save
        _message = message
        _selection = State(initialValue: initialURL)
    }

    var body: some View {
        let index = items.firstIndex { $0.id == selection }
        let current = index.map { items[$0] }
        VStack(spacing: 0) {
            GalleryDetailHeader(date: current?.date, position: (index ?? 0) + 1,
                                count: items.count, close: { dismiss() }) {
                if let current {
                    Menu {
                        ShareLink(item: current.url) { Label("Compartilhar", systemImage: "square.and.arrow.up") }
                        Button { save(current) } label: { Label("Salvar no Fotos", systemImage: "square.and.arrow.down") }
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                    }.accessibilityLabel("Opções da captura")
                }
            }
            TabView(selection: $selection) {
                ForEach(items) { item in
                    CapturePage(item: item, active: item.id == selection).tag(item.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            GalleryFilmstrip(items: items, selection: $selection) { item in
                Thumbnail(url: item.url, isVideo: item.isVideo)
            }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .alert("Momentra", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
}

private struct CapturePage: View {
    let item: OriginalFile
    let active: Bool
    @State private var preview: UIImage?
    @State private var player: AVPlayer?
    @State private var failed = false
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .scaleEffect(magnification)
                        .gesture(MagnifyGesture().updating($magnification) { value, scale, _ in
                            scale = min(5, max(1, value.magnification))
                        })
                } else if failed {
                    ContentUnavailableView("Não foi possível abrir a captura", systemImage: "photo.badge.exclamationmark")
                } else if active {
                    ProgressView("Abrindo captura…")
                } else {
                    Color.clear
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .task(id: active) {
            guard active else { player?.pause(); return }
            if item.isVideo {
                if player == nil { player = AVPlayer(url: item.url) }
            } else if preview == nil {
                let url = item.url
                let image = await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 2600
                          ] as CFDictionary) else { return nil as UIImage? }
                    return UIImage(cgImage: image)
                }.value
                if !Task.isCancelled { preview = image; failed = image == nil }
            }
        }.onDisappear { player?.pause() }
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
