import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A disposable cache for display thumbnails. The capture and archive stores own the originals.
actor GalleryThumbnailCache {
    static let gridDiskCountLimit = 400
    static let shared = GalleryThumbnailCache(directory: FileManager.default.urls(for: .cachesDirectory,
                                                                                  in: .userDomainMask).first?
        .appendingPathComponent("MomentraGalleryThumbnails-v1", isDirectory: true),
        diskCountLimit: gridDiskCountLimit)

    static let viewer = GalleryThumbnailCache(directory: FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask).first?.appendingPathComponent("MomentraGalleryPreviews-v1", isDirectory: true),
        diskByteLimit: 128 * 1024 * 1024, diskCountLimit: 128, memoryCostLimit: 32 * 1024 * 1024,
        diskEntryLimit: 4 * 1024 * 1024)

    private struct Flight {
        let generation = UUID()
        let task: Task<CGImage?, Error>
        var waiters: Set<UUID>
    }

    private struct DiskEntry {
        let url: URL
        let size: Int
        let date: Date
    }

    private let directory: URL?
    private let diskByteLimit: Int
    private let diskCountLimit: Int
    private let diskEntryLimit: Int
    private let memory = NSCache<NSString, CGImage>()
    private var flights: [String: Flight] = [:]
    private var diskEntries: [String: DiskEntry]?
    private var diskBytes = 0

    init(directory: URL?, diskByteLimit: Int = 32 * 1024 * 1024, diskCountLimit: Int = 400,
         memoryCostLimit: Int = 12 * 1024 * 1024, diskEntryLimit: Int = 1_048_576) {
        self.directory = directory
        self.diskByteLimit = max(0, diskByteLimit)
        self.diskCountLimit = max(0, diskCountLimit)
        self.diskEntryLimit = max(1, diskEntryLimit)
        memory.totalCostLimit = max(1, memoryCostLimit)
        memory.countLimit = 96
    }

    func image(forFile url: URL, isVideo: Bool, maximumPixels: Int,
               generate: @Sendable @escaping () async throws -> CGImage?) async throws -> CGImage? {
        guard let key = fileKey(url, isVideo: isVideo) else { return try await generate() }
        return try await image(for: key, maximumPixels: maximumPixels, generate: generate)
    }

    func cachedImage(forFile url: URL, isVideo: Bool, maximumPixels: Int) -> CGImage? {
        guard let key = fileKey(url, isVideo: isVideo) else { return nil }
        return cachedImage(for: key, maximumPixels: maximumPixels)
    }

    func cachedImage(for key: String, maximumPixels: Int) -> CGImage? {
        cachedFingerprint(fingerprint(for: key, maximumPixels: maximumPixels), maximumPixels: maximumPixels)
    }

    private func fileKey(_ url: URL, isVideo: Bool) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let date = values.contentModificationDate else { return nil }
        return "file|\(isVideo)|\(url.path)|\(size)|\(date.timeIntervalSinceReferenceDate)"
    }

    private func fingerprint(for key: String, maximumPixels: Int) -> String {
        SHA256.hash(data: Data("\(maximumPixels)|\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func cachedFingerprint(_ key: String, maximumPixels: Int) -> CGImage? {
        if let image = memory.object(forKey: key as NSString) { return image }
        guard let image = readDisk(key, maximumPixels: maximumPixels) else { return nil }
        storeMemory(image, key: key)
        return image
    }

    func image(for key: String, maximumPixels: Int,
               generate: @Sendable @escaping () async throws -> CGImage?) async throws -> CGImage? {
        try Task.checkCancellation()
        let fingerprint = fingerprint(for: key, maximumPixels: maximumPixels)
        if let image = cachedFingerprint(fingerprint, maximumPixels: maximumPixels) { return image }
        let waiter = UUID()
        var flight = flights[fingerprint] ?? Flight(task: Task.detached(priority: .utility) {
            try await generate()
        }, waiters: [])
        flight.waiters.insert(waiter)
        flights[fingerprint] = flight
        let generation = flight.generation
        let worker = flight.task
        return try await withTaskCancellationHandler {
            do {
                let image = try await worker.value
                if flights[fingerprint]?.generation == generation {
                    flights[fingerprint] = nil
                    if let image, max(image.width, image.height) <= maximumPixels { store(image, key: fingerprint) }
                }
                try Task.checkCancellation()
                return image
            } catch {
                if flights[fingerprint]?.generation == generation, !Task.isCancelled { flights[fingerprint] = nil }
                throw error
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiter, key: fingerprint, generation: generation) }
        }
    }

    private func cancelWaiter(_ waiter: UUID, key: String, generation: UUID) {
        guard var flight = flights[key], flight.generation == generation else { return }
        flight.waiters.remove(waiter)
        if flight.waiters.isEmpty {
            flight.task.cancel()
            flights[key] = nil
        } else {
            flights[key] = flight
        }
    }

    private func storeMemory(_ image: CGImage, key: String) {
        memory.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }

    private func readDisk(_ key: String, maximumPixels: Int) -> CGImage? {
        prepareDirectory()
        guard let entry = diskEntries?[key] else { return nil }
        guard let source = CGImageSourceCreateWithURL(entry.url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            removeDisk(key, entry: entry)
            return nil
        }
        let now = Date()
        if now.timeIntervalSince(entry.date) > 3600 {
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: entry.url.path)
            diskEntries?[key] = DiskEntry(url: entry.url, size: entry.size, date: now)
        }
        return image
    }

    private func store(_ image: CGImage, key: String) {
        storeMemory(image, key: key)
        guard let directory, diskCountLimit > 0, diskByteLimit > 0 else { return }
        prepareDirectory()
        let bytes = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(output), bytes.length <= min(diskByteLimit, diskEntryLimit) else { return }
        let url = directory.appendingPathComponent(key).appendingPathExtension("jpg")
        do {
            try (bytes as Data).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            diskBytes -= diskEntries?[key]?.size ?? 0
            diskEntries?[key] = DiskEntry(url: url, size: bytes.length, date: .now)
            diskBytes += bytes.length
            trimIfNeeded()
        } catch {
            // The memory cache remains usable when iOS has removed the disposable directory.
            diskEntries = nil
        }
    }

    private func prepareDirectory() {
        guard diskEntries == nil, let directory else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var cacheDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? cacheDirectory.setResourceValues(values)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys),
                                                      options: [.skipsHiddenFiles])) ?? []
        var entries: [String: DiskEntry] = [:]
        for file in files where file.pathExtension == "jpg" {
            let key = file.deletingPathExtension().lastPathComponent
            guard key.count == 64, let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
                  (1...diskEntryLimit).contains(size) else { continue }
            entries[key] = DiskEntry(url: file, size: size, date: values.contentModificationDate ?? .distantPast)
        }
        diskEntries = entries
        diskBytes = entries.values.reduce(0) { $0 + $1.size }
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        guard let entries = diskEntries, diskBytes > diskByteLimit || entries.count > diskCountLimit else { return }
        for (key, entry) in entries.sorted(by: { $0.value.date < $1.value.date }) {
            guard diskBytes > diskByteLimit || (diskEntries?.count ?? 0) > diskCountLimit else { break }
            removeDisk(key, entry: entry)
        }
    }

    private func removeDisk(_ key: String, entry: DiskEntry) {
        do {
            try FileManager.default.removeItem(at: entry.url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // iOS can reclaim the cache independently.
        } catch { return }
        diskEntries?[key] = nil
        diskBytes -= entry.size
    }
}
