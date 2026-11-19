import CoreGraphics
import Foundation
import XCTest
@testable import Momentra

final class GalleryThumbnailCacheTests: XCTestCase {
    func testReusesThumbnailAcrossCacheInstances() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try XCTUnwrap(bitmap())
        let recorder = Renders()
        let first = GalleryThumbnailCache(directory: directory)
        _ = try await first.image(for: "account|item|r1", maximumPixels: 80) {
            await recorder.countRender(image)
        }

        let reopened = GalleryThumbnailCache(directory: directory)
        let cached = try await reopened.image(for: "account|item|r1", maximumPixels: 80) {
            await recorder.countRender(image)
        }
        XCTAssertEqual(cached?.width, image.width)
        let renders = await recorder.count
        XCTAssertEqual(renders, 1)
    }

    func testRevisionIsPartOfTheKeyAndDiskEntriesAreBounded() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try XCTUnwrap(bitmap())
        let recorder = Renders()
        let cache = GalleryThumbnailCache(directory: directory, diskCountLimit: 1)
        for revision in ["r1", "r2"] {
            _ = try await cache.image(for: "account|item|\(revision)", maximumPixels: 80) {
                await recorder.countRender(image)
            }
        }
        let renders = await recorder.count
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(renders, 2)
        XCTAssertEqual(files.count, 1)
    }

    func testViewerCanReadAStoredPreviewOfflineAfterRelaunch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try XCTUnwrap(bitmap())
        let remoteKey = "cloud/account-a/item/r1"
        let cache = GalleryThumbnailCache(directory: directory, diskEntryLimit: 4 * 1024 * 1024)
        _ = try await cache.image(for: remoteKey, maximumPixels: 1800) { image }
        let reopened = GalleryThumbnailCache(directory: directory, diskEntryLimit: 4 * 1024 * 1024)
        let cached = try await reopened.image(for: remoteKey, maximumPixels: 1800) {
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(cached?.width, image.width)
        let wrongAccount = await reopened.cachedImage(for: "cloud/account-b/item/r1", maximumPixels: 1800)
        let wrongRevision = await reopened.cachedImage(for: "cloud/account-a/item/r2", maximumPixels: 1800)
        XCTAssertNil(wrongAccount)
        XCTAssertNil(wrongRevision)
    }

    func testConcurrentRequestsShareOneRender() async throws {
        let image = try XCTUnwrap(bitmap())
        let recorder = Renders()
        let cache = GalleryThumbnailCache(directory: nil)
        let render: @Sendable () async throws -> CGImage? = {
            try await Task.sleep(for: .milliseconds(60))
            return await recorder.countRender(image)
        }
        async let first = cache.image(for: "image", maximumPixels: 80, generate: render)
        async let second = cache.image(for: "image", maximumPixels: 80, generate: render)
        let images = try await (first, second)
        XCTAssertNotNil(images.0)
        XCTAssertNotNil(images.1)
        let renders = await recorder.count
        XCTAssertEqual(renders, 1)
    }

    private func bitmap() -> CGImage? {
        let context = CGContext(data: nil, width: 36, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: 36, height: 24))
        return context?.makeImage()
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private actor Renders {
        private(set) var count = 0

        func countRender(_ image: CGImage) -> CGImage {
            count += 1
            return image
        }
    }
}
