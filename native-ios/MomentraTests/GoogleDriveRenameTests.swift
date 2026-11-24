import XCTest
@testable import Momentra

private final class RenameURLProtocol: URLProtocol {
    static var oldName = ""
    static var newName = ""
    static var includeETag = true
    static var marked = true
    static var patchCount = 0
    static var matchHeader: String?
    static var renamed = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let patch = request.httpMethod == "PATCH"
        if patch { Self.patchCount += 1; Self.matchHeader = request.value(forHTTPHeaderField: "If-Match"); Self.renamed = true }
        let name = Self.renamed ? Self.newName : Self.oldName
        let marker = Self.marked ? "1" : "0"
        let body = Data("{\"id\":\"file123\",\"name\":\"\(name)\",\"mimeType\":\"image/jpeg\",\"size\":\"10\",\"sha256Checksum\":\"abc\",\"parents\":[\"folder\"],\"trashed\":false,\"appProperties\":{\"momentraArchivePhoto\":\"\(marker)\"}}".utf8)
        let headers = Self.includeETag ? ["ETag": "\"revision-1\""] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GoogleDriveRenameTests: XCTestCase {
    func testMetadataOnlyRenameRequiresAppMarkerAndETag() async throws {
        let id = UUID().uuidString
        RenameURLProtocol.oldName = "\(id)-stamped.jpg"
        RenameURLProtocol.newName = "01-01-1970 - Google Drive - 00-20-34 - \(id).1234-stamped.jpg"
        RenameURLProtocol.patchCount = 0; RenameURLProtocol.includeETag = true; RenameURLProtocol.marked = true; RenameURLProtocol.renamed = false
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RenameURLProtocol.self]
        let drive = GoogleDriveArchive(configuration: config)
        try await drive.renamePhoto(id: "file123", from: RenameURLProtocol.oldName, to: RenameURLProtocol.newName, accessToken: "token")
        XCTAssertEqual(RenameURLProtocol.patchCount, 1)
        XCTAssertNotNil(RenameURLProtocol.matchHeader)
        RenameURLProtocol.patchCount = 0; RenameURLProtocol.includeETag = false; RenameURLProtocol.renamed = false
        do { try await drive.renamePhoto(id: "file123", from: RenameURLProtocol.oldName, to: RenameURLProtocol.newName, accessToken: "token"); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(RenameURLProtocol.patchCount, 0)
        RenameURLProtocol.includeETag = true; RenameURLProtocol.marked = false
        do { try await drive.renamePhoto(id: "file123", from: RenameURLProtocol.oldName, to: RenameURLProtocol.newName, accessToken: "token"); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(RenameURLProtocol.patchCount, 0)
    }
}
