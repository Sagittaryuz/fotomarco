import XCTest
@testable import Momentra

private final class ShareDownloadURLProtocol: URLProtocol {
    static let body = Data(repeating: 0x41, count: 256 * 1024)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "\(Self.body.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for start in stride(from: 0, to: Self.body.count, by: 16 * 1024) {
            client?.urlProtocol(self, didLoad: Self.body.subdata(in: start..<min(start + 16 * 1024, Self.body.count)))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ShareDownloadProgressTests: XCTestCase {
    func testGoogleDriveDownloadReportsCompletionAfterFileIsAvailable() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ShareDownloadURLProtocol.self]
        let archive = GoogleDriveArchive(configuration: configuration)
        // URLProtocol does not guarantee intermediate URLSessionDownloadDelegate
        // callbacks. This checks the terminal event, not live network progress.
        let progress = expectation(description: "Download reports completion")
        progress.assertForOverFulfill = false
        let file = try await archive.downloadFile(id: "file123", accessToken: "test-token") { value in
            if value == 1 { progress.fulfill() }
        }
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try Data(contentsOf: file), ShareDownloadURLProtocol.body)
        await fulfillment(of: [progress], timeout: 5)
    }

    func testRedirectObserverRejectsForwarding() {
        let observer = ShareDownloadProgress { _ in }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://example.com/original")!
        let target = URL(string: "https://example.net/target")!
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        let task = session.downloadTask(with: original)
        var forwarded: URLRequest?
        var called = false
        observer.urlSession(session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: target)) { called = true; forwarded = $0 }
        XCTAssertTrue(called)
        XCTAssertNil(forwarded)
    }
}
