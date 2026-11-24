import XCTest
@testable import Momentra

final class OneDriveRenameTests: XCTestCase {
    func testRenameChecksFolderVersionAndPreservesFileIdentity() async throws {
        let captureID = UUID().uuidString
        let oldName = "\(captureID)-stamped.jpg"
        let newName = "01-01-1970 - OneDrive - 00-20-34 - \(captureID).1234-stamped.jpg"
        var renamed = false, patches = 0
        let transport: (URLRequest) async throws -> (Data, URLResponse) = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.host, "graph.microsoft.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            let body: [String: Any], status: Int
            if url.path.hasSuffix("/special/approot") { body = ["id": "folder", "name": "root", "folder": [:]]; status = 200 }
            else if url.path.hasSuffix("/items/file123") {
                if request.httpMethod == "PATCH" {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "revision")
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
                    XCTAssertEqual(payload, ["name": newName])
                    patches += 1; renamed = true
                }
                body = ["id": "file123", "name": renamed ? newName : oldName, "size": 10,
                        "file": [:], "eTag": "revision", "parentReference": ["id": "folder"]]; status = 200
            } else { body = [:]; status = 404 }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            return (try JSONSerialization.data(withJSONObject: body), response)
        }
        try await OneDriveArchive().renamePhoto(id: "file123", from: oldName, to: newName, accessToken: "token", transport: transport)
        XCTAssertEqual(patches, 1)
    }

    func testRejectsDifferentCaptureBeforeSendingAnyRequest() async throws {
        let old = "\(UUID().uuidString)-stamped.jpg", new = "\(UUID().uuidString)-stamped.jpg"
        do {
            try await OneDriveArchive().renamePhoto(id: "file123", from: old, to: new, accessToken: "token", transport: { _ in
                XCTFail("Unexpected request"); throw OneDriveArchive.Failure.integrity
            })
            XCTFail("Expected invalid name")
        } catch OneDriveArchive.Failure.invalidName {} catch { XCTFail("Unexpected error") }
    }
}
