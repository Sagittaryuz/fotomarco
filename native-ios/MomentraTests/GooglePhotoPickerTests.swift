import XCTest
@testable import Momentra

private final class PickerURLProtocol: URLProtocol {
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

final class GooglePhotoPickerTests: XCTestCase {
    func testSessionDurationAndUntrustedPickerURLs() throws {
        let data = Data(#"{"id":"one","pickerUri":"https://photos.google.com/picker","pollingConfig":{"pollInterval":"3.5s","timeoutIn":"60s"}}"#.utf8)
        let item = try JSONDecoder().decode(GooglePickerSession.self, from: data)
        XCTAssertEqual(item.pickerURL?.host, "photos.google.com")
        XCTAssertEqual(GooglePickerSession.duration(item.pollingConfig!.pollInterval), 3.5)
        XCTAssertNil(GooglePickerSession.duration("-1s"))
        XCTAssertNil(GooglePickerSession.duration("nan"))
        let bad = Data(#"{"id":"one","pickerUri":"https://photos.google.com.evil.example/x"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(GooglePickerSession.self, from: bad).pickerURL)
    }

    func testSelectedPhotoRequiresTrustedHost() throws {
        let good = Data(#"{"id":"one","type":"PHOTO","createTime":"2026-11-16T23:05:00Z","mediaFile":{"baseUrl":"https://lh3.googleusercontent.com/p/abc","mimeType":"image/jpeg"}}"#.utf8)
        let photo = try JSONDecoder().decode(GooglePickedPhoto.self, from: good)
        XCTAssertEqual(photo.downloadURL?.absoluteString, "https://lh3.googleusercontent.com/p/abc=d")
        XCTAssertNotNil(photo.creationDate)
        let bad = Data(#"{"id":"one","type":"PHOTO","mediaFile":{"baseUrl":"https://evil.googleusercontent.com/p/abc","mimeType":"image/jpeg"}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(GooglePickedPhoto.self, from: bad).downloadURL)
    }

    func testCreatesSinglePhotoSessionWithBearerToken() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PickerURLProtocol.self]
        PickerURLProtocol.responseBody = Data(#"{"id":"session_1","pickerUri":"https://photos.google.com/picker"}"#.utf8)
        let result = try await GooglePhotoPickerClient(token: "test-token", configuration: config).create()
        XCTAssertEqual(result.id, "session_1")
        let request = try XCTUnwrap(PickerURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://photospicker.googleapis.com/v1/sessions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }
}
