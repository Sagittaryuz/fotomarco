import XCTest
import AVFoundation
import UIKit
import CoreVideo
@testable import Momentra

final class VideoStampRendererTests: XCTestCase {
    func testExportStampsVideoAndPreservesOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("original.mov")
        let output = root.appendingPathComponent("stamped.mov")
        try await makeVideo(at: source)
        let snapshot = StampSnapshot(capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                     gpsEnabled: false, location: nil, heading: nil)
        try await VideoStampRenderer.export(source: source, destination: output, snapshot: snapshot, map: nil, address: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let frame = try generator.copyCGImage(at: CMTime(seconds: 0.25, preferredTimescale: 600), actualTime: nil)
        XCTAssertGreaterThan(try brightPixels(in: frame), 15, "O quadro deve conter o texto claro do carimbo")
    }

    func testMissingSourceDoesNotCreateAnOutput() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("missing.mov")
        let output = root.appendingPathComponent("output.mov")
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, location: nil, heading: nil)
        do {
            try await VideoStampRenderer.export(source: source, destination: output, snapshot: snapshot, map: nil, address: nil)
            XCTFail("Arquivo ausente deve falhar")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160,
            AVVideoHeightKey: 120
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160,
            kCVPixelBufferHeightKey as String: 120
        ])
        guard writer.canAdd(input) else { throw NSError(domain: "VideoTest", code: 1) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "VideoTest", code: 2) }
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 160, 120, kCVPixelFormatType_32BGRA,
                                  nil, &pixel) == kCVReturnSuccess, let pixel else {
            throw NSError(domain: "VideoTest", code: 3)
        }
        CVPixelBufferLockBaseAddress(pixel, [])
        if let base = CVPixelBufferGetBaseAddress(pixel) {
            let rowBytes = CVPixelBufferGetBytesPerRow(pixel)
            for y in 0..<120 {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<160 {
                    row[x * 4] = 90; row[x * 4 + 1] = 180; row[x * 4 + 2] = 140; row[x * 4 + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for index in 0..<15 {
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, attempts < 1000 else { throw writer.error ?? NSError(domain: "VideoTest", code: 7) }
                attempts += 1
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 15)) else {
                throw writer.error ?? NSError(domain: "VideoTest", code: 4)
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "VideoTest", code: 5) }
    }

    private func brightPixels(in image: CGImage) throws -> Int {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "VideoTest", code: 6)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: bytes.count, by: 4).filter {
            bytes[$0] > 205 && bytes[$0 + 1] > 205 && bytes[$0 + 2] > 205
        }.count
    }
}
