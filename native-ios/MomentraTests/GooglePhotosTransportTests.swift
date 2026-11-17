import XCTest
@testable import Momentra

private final class PhotoURLProtocol: URLProtocol {
    static var responseBody = Data()
    static var capturedRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.capturedRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GooglePhotosTransportTests: XCTestCase {
    private func makeTransport() -> GooglePersonalPhotoTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PhotoURLProtocol.self]
        return GooglePersonalPhotoTransport(token: "test-token", configuration: configuration)
    }

    func testUploadUsesExpectedEndpointAndHeaders() async throws {
        PhotoURLProtocol.responseBody = Data("sample-upload-token".utf8)
        PhotoURLProtocol.capturedRequest = nil
        let token = try await makeTransport().uploadBytes(Data([0xff, 0xd8, 0xff, 0xd9]))
        XCTAssertEqual(token, "sample-upload-token")
        let request = try XCTUnwrap(PhotoURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://photoslibrary.googleapis.com/v1/uploads")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Upload-Protocol"), "raw")
    }

    func testOversizedResponseIsRejected() async {
        PhotoURLProtocol.responseBody = Data(repeating: 65, count: 8193)
        do {
            _ = try await makeTransport().uploadBytes(Data([0xff, 0xd8, 0xff, 0xd9]))
            XCTFail("A resposta acima do limite não deveria ser aceita")
        } catch {}
    }

    func testListingEncodesPaginationAndUsesLibraryEndpoint() async throws {
        PhotoURLProtocol.responseBody = Data(#"{"mediaItems":[],"nextPageToken":"next"}"#.utf8)
        PhotoURLProtocol.capturedRequest = nil
        let page = try await makeTransport().listAppPhotos(pageToken: "a+b&c")
        XCTAssertEqual(page.nextPageToken, "next")
        let request = try XCTUnwrap(PhotoURLProtocol.capturedRequest)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "photoslibrary.googleapis.com")
        XCTAssertEqual(url.path, "/v1/mediaItems")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first(where: { $0.name == "pageToken" })?.value, "a+b&c")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }
}
