import SwiftUI
import Photos
import ImageIO
import AVKit

struct OriginalFile: Identifiable {
    let url: URL
    let isVideo: Bool
    let isProcessed: Bool
    let date: Date?
    var trashedAt: Date? = nil
    var id: URL { url }
}

enum OriginalStore {
    private static let folders = [("Originals", false, false), ("Processed", false, true),
                                  ("Videos", true, false), ("ProcessedVideos", true, true)]
    static let retention: TimeInterval = 30 * 86_400

    static func moveToTrash(_ item: OriginalFile) throws {
        let manager = FileManager.default
        let folder = item.url.deletingLastPathComponent()
        let root = folder.deletingLastPathComponent()
        let archive = CloudArchiveJournal(root: root)
        try archive.serializeCleanup {
            if let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent),
               archive.hasPendingDelivery(id: id) { throw CocoaError(.fileWriteFileExists) }
            let key = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
            let destination = root.appendingPathComponent("CaptureTrash", isDirectory: true)
                .appendingPathComponent(folder.lastPathComponent, isDirectory: true)
                .appendingPathComponent(key, isDirectory: true)
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            do {
                try manager.moveItem(at: item.url, to: destination.appendingPathComponent(item.url.lastPathComponent))
            } catch {
                try? manager.removeItem(at: destination)
                throw error
            }
        }
    }

    static func restore(_ item: OriginalFile) throws {
        let manager = FileManager.default
        let entry = item.url.deletingLastPathComponent()
        let folder = entry.deletingLastPathComponent()
        let root = folder.deletingLastPathComponent().deletingLastPathComponent()
        try CloudArchiveJournal(root: root).serializeCleanup {
            guard let trashedAt = item.trashedAt, Date().timeIntervalSince(trashedAt) < retention else {
                throw CocoaError(.fileNoSuchFile)
            }
            let destination = root.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            try manager.moveItem(at: item.url, to: destination.appendingPathComponent(item.url.lastPathComponent))
            try? manager.removeItem(at: entry)
        }
    }

    static func files(inTrash: Bool = false, now: Date = .now, root: URL? = nil) throws -> [OriginalFile] {
        let manager = FileManager.default
        let documents = try root ?? manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = inTrash ? documents.appendingPathComponent("CaptureTrash", isDirectory: true) : documents
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        return try CloudArchiveJournal(root: documents).serializeCleanup {
            try folders.flatMap { folder, isVideo, isProcessed -> [OriginalFile] in
                let directory = root.appendingPathComponent(folder, isDirectory: true)
                guard manager.fileExists(atPath: directory.path) else { return [] }
                let entries = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys),
                                                             options: [.skipsHiddenFiles])
                func file(_ url: URL, trashedAt: Date?) throws -> OriginalFile? {
                    let info = try url.resourceValues(forKeys: keys)
                    guard info.isRegularFile == true else { return nil }
                    return OriginalFile(url: url, isVideo: isVideo, isProcessed: isProcessed,
                                        date: info.contentModificationDate, trashedAt: trashedAt)
                }
                if !inTrash { return try entries.compactMap { try file($0, trashedAt: nil) } }
                return try entries.flatMap { entry -> [OriginalFile] in
                    guard let prefix = entry.lastPathComponent.split(separator: "-").first,
                          let epoch = TimeInterval(prefix), epoch.isFinite, epoch > 0,
                          (try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({
                              $0.isDirectory == true && $0.isSymbolicLink != true
                          }) == true else { return [] }
                    let deleted = Date(timeIntervalSince1970: epoch)
                    let children = try manager.contentsOfDirectory(at: entry, includingPropertiesForKeys: Array(keys),
                                                                  options: [.skipsHiddenFiles])
                    if now.timeIntervalSince(deleted) >= retention {
                        for url in children where (try? file(url, trashedAt: deleted)) != nil {
                            try manager.removeItem(at: url)
                        }
                        if (try? manager.contentsOfDirectory(atPath: entry.path).isEmpty) == true {
                            try? manager.removeItem(at: entry)
                        }
                        return []
                    }
                    return try children.compactMap { try file($0, trashedAt: deleted) }
                }
            }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        }
    }
}

struct CaptureTextPanel: View {
    let url: URL
    @State private var text: String?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                ContentUnavailableView("Não foi possível ler o texto", systemImage: "text.viewfinder")
            } else if let text {
                if text.isEmpty {
                    ContentUnavailableView("Nenhum texto reconhecido", systemImage: "text.viewfinder")
                } else {
                    ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                    Button("Copiar texto") { FotomarcoHaptics.play(.buttons); UIPasteboard.general.string = text }.padding()
                }
            } else {
                ProgressView("Lendo texto…")
            }
        }
        .task(id: url) {
            do { text = try await Task.detached(priority: .userInitiated) { try GalleryPhotoActions.recognizeText(in: url) }.value }
            catch { failed = true }
        }
    }
}

struct CapturePage: View {
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
            guard active else { player?.pause(); preview = nil; return }
            if item.isVideo {
                if player == nil { player = AVPlayer(url: item.url) }
            } else if preview == nil {
                let url = item.url
                if let thumbnail = await GalleryThumbnailCache.shared.cachedImage(forFile: url,
                    isVideo: false, maximumPixels: 320), !Task.isCancelled {
                    preview = UIImage(cgImage: thumbnail)
                }
                let image = try? await GalleryThumbnailCache.viewer.image(forFile: url, isVideo: false, maximumPixels: 2600) {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2600
                    ] as CFDictionary)
                }
                if !Task.isCancelled {
                    if let image { preview = UIImage(cgImage: image) }
                    failed = preview == nil
                }
            }
        }.onDisappear { player?.pause() }
    }
}

struct Thumbnail: View {
    let url: URL
    let isVideo: Bool
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(.gray.opacity(0.2))
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: isVideo ? "video.fill" : "photo").foregroundStyle(.secondary) }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: url) {
            let file = url
            let video = isVideo
            let pixels = video ? 256 : 320
            let thumbnail = try? await GalleryThumbnailCache.shared.image(forFile: file, isVideo: video,
                                                                           maximumPixels: pixels) {
                if video {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: pixels, height: pixels)
                    return try await generator.image(at: .zero).image
                }
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels
                ] as CFDictionary)
            }
            if !Task.isCancelled { image = thumbnail.map { UIImage(cgImage: $0) } }
        }
    }
}
