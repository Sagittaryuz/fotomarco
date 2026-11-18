import XCTest
@testable import Momentra

final class CloudPhotoPageTests: XCTestCase {
    func testFiltersNonPhotosAndUntrustedLinks() throws {
        let json = #"{"mediaItems":[{"id":"one","filename":"foto.jpg","mimeType":"image/jpeg","baseUrl":"https://lh3.googleusercontent.com/photo","productUrl":"https://photos.google.com/photo/one"},{"id":"two","mimeType":"video/mp4"},{"id":"three","mimeType":"image/jpeg","baseUrl":"https://googleusercontent.com.evil.example/photo","productUrl":"https://photos.google.com.evil.example/photo"}],"nextPageToken":"next"}"#
        let page = try CloudPhotoPage.parse(Data(json.utf8))
        XCTAssertEqual(page.photos.count, 2)
        XCTAssertEqual(page.photos[0].thumbnailURL?.absoluteString, "https://lh3.googleusercontent.com/photo=w360-h360-c")
        XCTAssertEqual(page.photos[0].productURL?.host, "photos.google.com")
        XCTAssertNil(page.photos[1].thumbnailURL)
        XCTAssertNil(page.photos[1].productURL)
        XCTAssertEqual(page.nextPageToken, "next")
    }

    func testRejectsCredentialsOrQueryInThumbnailURL() {
        XCTAssertNil(CloudPhotoPage.thumbnailURL("https://user@lh3.googleusercontent.com/p"))
        XCTAssertNil(CloudPhotoPage.thumbnailURL("https://lh3.googleusercontent.com/p?x=1"))
        XCTAssertNil(CloudPhotoPage.thumbnailURL("http://lh3.googleusercontent.com/p"))
    }

    func testPhotoCreationDateIsReadFromGoogleMetadata() throws {
        let json = #"{"mediaItems":[{"id":"one","mimeType":"image/jpeg","mediaMetadata":{"creationTime":"2026-11-17T08:50:59.123Z"}},{"id":"two","mimeType":"image/jpeg"}]}"#
        let page = try CloudPhotoPage.parse(Data(json.utf8))
        XCTAssertNotNil(page.photos[0].date)
        XCTAssertNil(page.photos[1].date)
    }
}
