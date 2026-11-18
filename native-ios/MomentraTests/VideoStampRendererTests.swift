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

    func testPortraitTransformPreservesFrameDimensionsAndStamp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let landscape = root.appendingPathComponent("landscape.mov")
        let portrait = root.appendingPathComponent("portrait.mov")
        let output = root.appendingPathComponent("stamped.mov")
        try await makeVideo(at: landscape)
        let asset = AVURLAsset(url: landscape)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        let rotated = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try rotated.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        rotated.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 120, ty: 0)
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        exporter.outputURL = portrait
        exporter.outputFileType = .mov
        await withCheckedContinuation { continuation in exporter.exportAsynchronously { continuation.resume() } }
        guard exporter.status == .completed else { throw exporter.error ?? NSError(domain: "VideoOrientationTest", code: 1) }
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, location: nil, heading: nil)
        try await VideoStampRenderer.export(source: portrait, destination: output, snapshot: snapshot, map: nil, address: nil)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.appliesPreferredTrackTransform = true
        let frame = try generator.copyCGImage(at: CMTime(seconds: 0.25, preferredTimescale: 600), actualTime: nil)
        XCTAssertEqual(frame.width, 120)
        XCTAssertEqual(frame.height, 160)
        XCTAssertGreaterThan(try brightPixels(in: frame), 15)
        XCTAssertTrue(FileManager.default.fileExists(atPath: portrait.path))
    }

    func testStampedVideoRetainsAudibleTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let silent = root.appendingPathComponent("silent.mov")
        let audio = root.appendingPathComponent("tone.caf")
        let source = root.appendingPathComponent("with-audio.mov")
        let output = root.appendingPathComponent("stamped.mov")
        try await makeVideo(at: silent)
        try makeTone(at: audio)
        try await combine(video: silent, audio: audio, output: source)
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, location: nil, heading: nil)
        try await VideoStampRenderer.export(source: source, destination: output, snapshot: snapshot, map: nil, address: nil)
        let exported = AVURLAsset(url: output)
        let audioTracks = try await exported.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(audioTracks.first)
        let reader = try AVAssetReader(asset: exported)
        let audioOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        XCTAssertTrue(reader.canAdd(audioOutput))
        reader.add(audioOutput)
        XCTAssertTrue(reader.startReading())
        var nonzeroBytes = 0
        while let sample = audioOutput.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let size = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: size)
            guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: &bytes) == kCMBlockBufferNoErr else {
                throw NSError(domain: "VideoAudioTest", code: 1)
            }
            nonzeroBytes += bytes.filter { $0 != 0 }.count
        }
        XCTAssertGreaterThan(nonzeroBytes, 100, "O áudio gravado deve permanecer audível")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeTone(at url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(buffer.frameLength) {
            channel[index] = Float(sin(2 * Double.pi * 440 * Double(index) / 44_100) * 0.4)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func combine(video: URL, audio: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        let duration = CMTimeMinimum(try await videoAsset.load(.duration), try await audioAsset.load(.duration))
        let composition = AVMutableComposition()
        let outputVideo = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let outputAudio = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try outputVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        try outputAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        exporter.outputURL = output
        exporter.outputFileType = .mov
        await withCheckedContinuation { continuation in exporter.exportAsynchronously { continuation.resume() } }
        guard exporter.status == .completed else { throw exporter.error ?? NSError(domain: "VideoAudioTest", code: 2) }
    }

    func testCancelledExportKeepsOriginalAndDoesNotPublishOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("original.mov")
        let output = root.appendingPathComponent("stamped.mov")
        try await makeVideo(at: source)
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, location: nil, heading: nil)
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await VideoStampRenderer.export(source: source, destination: output, snapshot: snapshot, map: nil, address: nil)
        }
        do { try await work.value; XCTFail("A exportação cancelada não deve ser publicada") }
        catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
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
