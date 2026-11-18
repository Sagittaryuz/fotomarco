import AVFoundation
import CoreImage
import UIKit

enum VideoStampRenderer {
    enum Failure: Error { case missingVideo, invalidSize, overlay, exporter, outputExists, incomplete }

    /// The source is never removed. A completed output is published only after
    /// checking duration, video and audio track presence.
    static func export(source: URL, destination: URL, snapshot: StampSnapshot,
                       map: UIImage?, address: String?) async throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.outputExists }
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.missingVideo }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: natural).applying(transform).standardized
        let size = CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
        guard size.width > 0, size.height > 0, size.width <= 10000, size.height <= 10000 else { throw Failure.invalidSize }
        guard let image = StampRenderer.overlay(size: size, snapshot: snapshot, map: map, address: address),
              let cgImage = image.cgImage else { throw Failure.overlay }
        let stamp = CIImage(cgImage: cgImage)
        let composition = AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let extent = request.sourceImage.extent
            let overlay = stamp.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            request.finish(with: overlay.composited(over: request.sourceImage).cropped(to: extent), context: nil)
        })
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
              exporter.supportedFileTypes.contains(.mov) else { throw Failure.exporter }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let temporary = directory.appendingPathComponent("." + UUID().uuidString + ".partial.mov")
        defer { try? FileManager.default.removeItem(at: temporary) }
        exporter.outputURL = temporary
        exporter.outputFileType = .mov
        exporter.videoComposition = composition
        try Task.checkCancellation()
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return }
            await withCheckedContinuation { continuation in
                exporter.exportAsynchronously { continuation.resume() }
                if Task.isCancelled { exporter.cancelExport() }
            }
        } onCancel: {
            exporter.cancelExport()
        }
        try Task.checkCancellation()
        guard exporter.status == .completed else { throw exporter.error ?? Failure.incomplete }
        let finished = AVURLAsset(url: temporary)
        let sourceDuration = try await asset.load(.duration)
        let outputDuration = try await finished.load(.duration)
        let inputAudio = try await asset.loadTracks(withMediaType: .audio)
        let outputAudio = try await finished.loadTracks(withMediaType: .audio)
        let outputVideo = try await finished.loadTracks(withMediaType: .video)
        guard !outputVideo.isEmpty, (inputAudio.isEmpty || !outputAudio.isEmpty),
              sourceDuration.seconds.isFinite, outputDuration.seconds.isFinite,
              abs(sourceDuration.seconds - outputDuration.seconds) < 0.25 else { throw Failure.incomplete }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: destination)
        try? (destination as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication,
                                                    forKey: .fileProtectionKey)
    }
}
