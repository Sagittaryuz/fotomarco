import XCTest
import CoreLocation
@testable import Momentra

@MainActor
final class ForecastClientTests: XCTestCase {
    func testConsentAndCachePreventUnnecessaryRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ForecastCacheStore(root: root)
        let now = ISO8601DateFormatter().date(from: "2026-11-16T20:30:00Z")!
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.123456, longitude: -51.987654), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: now)
        let body = Data("""
        {"properties":{"meta":{"updated_at":"2026-11-16T19:00:00Z","units":{"air_temperature":"celsius"}},"timeseries":[{"time":"2026-11-16T20:00:00Z","data":{"instant":{"details":{"air_temperature":22}}}}]}}
        """.utf8)
        var calls = 0
        let transport: ForecastClient.Transport = { request in
            calls += 1
            XCTAssertTrue(request.url!.absoluteString.contains("lat=-17.1234&lon=-51.9876"))
            XCTAssertTrue((request.value(forHTTPHeaderField: "User-Agent") ?? "").contains("Momentra/"))
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await ForecastClient.fetch(location: location, now: now, consent: false, isForeground: { true }, store: store, transport: transport)
            XCTFail("A consulta não pode ocorrer sem aceite")
        } catch {}
        XCTAssertEqual(calls, 0)
        do {
            _ = try await ForecastClient.fetch(location: location, now: now, consent: true, isForeground: { false }, store: store, transport: transport)
            XCTFail("A consulta não pode ocorrer em segundo plano")
        } catch {}
        XCTAssertEqual(calls, 0)
        let first = try await ForecastClient.fetch(location: location, now: now, consent: true, isForeground: { true }, store: store, transport: transport)
        XCTAssertEqual(first.temperatureC, 22)
        let later = now.addingTimeInterval(60)
        let recentLocation = CLLocation(coordinate: location.coordinate, altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: later)
        let cached = try await ForecastClient.fetch(location: recentLocation, now: later, consent: true, isForeground: { true }, store: store, transport: transport)
        XCTAssertEqual(cached.temperatureC, 22)
        XCTAssertEqual(calls, 1)
    }

    func testRateLimitAndClockReversalAreConservative() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let lock = ForecastCacheRecord(requestedAt: now, retryAt: now.addingTimeInterval(10800), lastModified: nil, responseBody: nil)
        XCTAssertFalse(lock.mayRequest(at: now.addingTimeInterval(-1)))
        XCTAssertFalse(lock.mayRequest(at: now.addingTimeInterval(10799)))
        XCTAssertTrue(lock.mayRequest(at: now.addingTimeInterval(10800)))
        let retry = ForecastCachePolicy.retryDate(now: now, expires: nil, retryAfter: "172800", status: 429)
        XCTAssertEqual(retry.timeIntervalSince(now), 172800, accuracy: 0.001)
    }

    func testCorruptCacheDoesNotPermitRequest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ForecastCacheStore(root: root)
        let now = Date()
        let bad = ForecastCacheRecord(requestedAt: now, retryAt: now, lastModified: nil, responseBody: nil)
        try store.write(bad, key: "-17.1000,-51.1000")
        XCTAssertThrowsError(try store.read("-17.1000,-51.1000"))
    }
}
