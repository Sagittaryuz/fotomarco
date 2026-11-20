import XCTest
import CoreLocation
@testable import Momentra

final class StampSnapshotTests: XCTestCase {
    func testWorkReportProducesOverlayAndRejectsInsufficientSpace() throws {
        var layout = StampLayout()
        layout.template = .workReport
        layout.setTemplateValue("Obra A", for: "Projeto")
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, location: nil, heading: nil, layout: layout)
        let overlay = try XCTUnwrap(StampRenderer.overlay(size: CGSize(width: 400, height: 600), snapshot: snapshot, map: nil, address: nil))
        XCTAssertEqual(overlay.size, CGSize(width: 400, height: 600))
        XCTAssertNil(StampRenderer.overlay(size: CGSize(width: 20, height: 20), snapshot: snapshot, map: nil, address: nil))
    }

    func testFixedTemplatesProduceAnOverlayWithoutLocation() throws {
        for template in [StampLayout.Template.workReport, .spreadsheet, .locationWeather, .timeLocation, .custom, .map, .largeMap, .visit, .delivery, .clean, .checkIn, .patrol, .completed, .deliveryProof, .inspection, .portrait, .shopee, .construction] {
            var layout = StampLayout()
            layout.template = template
            let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, location: nil, heading: nil, layout: layout)
            XCTAssertNotNil(StampRenderer.overlay(size: CGSize(width: 400, height: 600), snapshot: snapshot, map: nil, address: nil), "\(template.rawValue)")
        }
    }
    func testFixedTemplateContentUsesSelectedFieldsAndRespectsLocationPermission() {
        var layout = StampLayout()
        layout.template = .workReport
        layout.setTemplateValue("Obra A", for: "Projeto")
        layout.setTemplateValue("Piso", for: "Inspeção")
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, addressEnabled: true,
                                     location: CLLocation(latitude: -17.9, longitude: -51.7), heading: nil, layout: layout)
        let content = snapshot.templateContent(address: "Endereço antigo")
        XCTAssertEqual(content.template, .workReport)
        XCTAssertEqual(content.customFields["Projeto"], "Obra A")
        XCTAssertEqual(content.customFields["Inspeção"], "Piso")
        XCTAssertNil(content.address)
        XCTAssertNil(content.coordinate)
        XCTAssertFalse(content.date.isEmpty)
        XCTAssertFalse(content.time.isEmpty)
    }
    func testDisabledGPSNeverAppearsInStamp() {
        let now = Date()
        let location = CLLocation(latitude: -17.9, longitude: -51.7)
        let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: false, mapEnabled: true, addressEnabled: true, location: location, heading: nil)
        XCTAssertNil(snapshot.location)
        XCTAssertFalse(snapshot.mapEnabled)
        XCTAssertFalse(snapshot.addressEnabled)
        XCTAssertTrue(snapshot.lines.contains("Localização desativada"))
        let completed = expectation(description: "address skipped when GPS disabled")
        StampAddress.load(snapshot: snapshot, queue: .main) { address in
            XCTAssertNil(address)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
    }

    func testOldOrFutureLocationIsRejected() {
        let now = Date()
        func makeLocation(_ time: Date) -> CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.9, longitude: -51.7), altitude: 700, horizontalAccuracy: 8, verticalAccuracy: 5, timestamp: time)
        }
        XCTAssertNil(StampSnapshot(capturedAt: now, gpsEnabled: true, location: makeLocation(now.addingTimeInterval(-61)), heading: nil).location)
        XCTAssertNil(StampSnapshot(capturedAt: now, gpsEnabled: true, location: makeLocation(now.addingTimeInterval(1)), heading: nil).location)
        let fresh = StampSnapshot(capturedAt: now, gpsEnabled: true, location: makeLocation(now), heading: nil)
        XCTAssertNotNil(fresh.location)
        XCTAssertTrue(fresh.lines.contains { $0.contains("Precisão: ±8 m") })
        XCTAssertTrue(fresh.lines.contains { $0.contains("Altitude:") })
    }

    func testProfileTextIsBoundedAndSingleLine() {
        let snapshot = StampSnapshot(capturedAt: Date(), gpsEnabled: false, title: String(repeating: "A", count: 45), note: "nota\nseguinte", location: nil, heading: nil)
        XCTAssertEqual(snapshot.title.count, 40)
        XCTAssertEqual(snapshot.note, "nota seguinte")
        XCTAssertEqual(snapshot.lines.first, snapshot.title + " · " + snapshot.note)
    }

    func testInformationIncludesAddressAndWeatherInAtMostFiveLines() {
        let now = Date()
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.9, longitude: -51.7), altitude: 700,
                                  horizontalAccuracy: 8, verticalAccuracy: 5, timestamp: now)
        let forecast = Forecast(validAt: now, updatedAt: now, temperatureC: 27, humidityPercent: 60,
                                windMetersPerSecond: 2, seaLevelPressureHpa: 1012)
        let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: true, addressEnabled: true,
                                     title: "Obra", note: "Pavimento", forecast: forecast, location: location, heading: nil)
        let lines = snapshot.informationLines(address: "Rua Exemplo, 123")
        XCTAssertLessThanOrEqual(lines.count, 5)
        XCTAssertTrue(lines.contains { $0.contains("Rua Exemplo") })
        XCTAssertTrue(lines.contains { $0.contains("27.0 °C") })
        XCTAssertTrue(lines.contains { $0.contains("Altitude:") })
        XCTAssertFalse(lines.joined().contains("Previsão válida em"))
        XCTAssertFalse(lines.contains { $0.contains("\n") })
    }

    func testStampPositionHasSafeDefault() {
        let top = StampSnapshot(capturedAt: Date(), gpsEnabled: false, position: "top", location: nil, heading: nil)
        let invalid = StampSnapshot(capturedAt: Date(), gpsEnabled: false, position: "unexpected", location: nil, heading: nil)
        XCTAssertEqual(top.position, "top")
        XCTAssertEqual(invalid.position, "bottom")
    }
}
