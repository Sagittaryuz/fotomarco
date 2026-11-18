import XCTest
@testable import Momentra

private actor AlbumTransportStub: GoogleAlbumTransport {
    var albums: [GoogleAlbum] = []
    var createCalls = 0
    var failCreate = false

    func albumPage(pageToken: String?) async throws -> GoogleAlbumPage {
        GoogleAlbumPage(albums: albums, nextPageToken: nil)
    }
    func createAlbum(title: String) async throws -> GoogleAlbum {
        createCalls += 1
        if failCreate { throw URLError(.timedOut) }
        let album = GoogleAlbum(id: "album1", title: title, isWriteable: true)
        albums.append(album)
        return album
    }
    func getAlbum(id: String) async throws -> GoogleAlbum {
        guard let album = albums.first(where: { $0.id == id }) else { throw URLError(.fileDoesNotExist) }
        return album
    }
    func failNextCreate() { failCreate = true }
    func count() -> Int { createCalls }
}

final class GoogleMomentraAlbumTests: XCTestCase {
    func testAlbumIsCreatedOnceAndReusedForAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = AlbumTransportStub()
        let coordinator = GoogleAlbumCoordinator()
        let first = try await coordinator.resolve(directory: directory, owner: "user", transport: transport, accountIsCurrent: { _ in true })
        let second = try await coordinator.resolve(directory: directory, owner: "user", transport: transport, accountIsCurrent: { _ in true })
        let count = await transport.count()
        XCTAssertEqual(first, "album1")
        XCTAssertEqual(second, first)
        XCTAssertEqual(count, 1)
    }

    func testAmbiguousCreationDoesNotCreateAnotherAlbum() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = AlbumTransportStub()
        await transport.failNextCreate()
        let coordinator = GoogleAlbumCoordinator()
        for _ in 0..<2 {
            do {
                _ = try await coordinator.resolve(directory: directory, owner: "user", transport: transport, accountIsCurrent: { _ in true })
                XCTFail("A criação incerta não deve ser aceita")
            } catch {}
        }
        let count = await transport.count()
        XCTAssertEqual(count, 1)
    }

    func testAccountChangeStopsBeforeCreation() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = AlbumTransportStub()
        let coordinator = GoogleAlbumCoordinator()
        do {
            _ = try await coordinator.resolve(directory: directory, owner: "user", transport: transport, accountIsCurrent: { _ in false })
            XCTFail("Não deve criar álbum para uma conta diferente")
        } catch {}
        let count = await transport.count()
        XCTAssertEqual(count, 0)
    }
}
