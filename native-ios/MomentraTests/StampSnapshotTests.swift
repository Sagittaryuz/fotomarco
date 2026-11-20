import XCTest
import CoreLocation
import UIKit
@testable import Momentra

final class StampSnapshotTests: XCTestCase {
    func testSeparateStampUsesDateLocationWeatherAndCustomNote() throws {
        let date = Date(timeIntervalSince1970: 1_795_176_000)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.88, longitude: -51.71),
                                  altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: date)
        let forecast = Forecast(validAt: date, updatedAt: date, temperatureC: 25, humidityPercent: 60,
                                windMetersPerSecond: 3, seaLevelPressureHpa: 1012)
        var layout = StampLayout(); layout.mode = .separate
        let snapshot = StampSnapshot(capturedAt: date, gpsEnabled: true, addressEnabled: true,
                                     cachedAddress: "Rua Um, 123", title: "Não é a nota", note: "Condomínio Hamoa Jataí",
                                     pressure: PressureSample(hectopascals: 930, observedAt: date), forecast: forecast,
                                     location: location, heading: nil, layout: layout)
        let content = snapshot.separateInformation(address: "Rua Um, 123")
        XCTAssertEqual(content.address, "Rua Um, 123")
        XCTAssertEqual(content.coordinate, "-17.880000, -51.710000")
        XCTAssertTrue(content.weather?.contains("930.0 hPa") == true)
        XCTAssertTrue(content.weather?.contains("10.8 km/h") == true)
        XCTAssertEqual(content.note, "Condomínio Hamoa Jataí")
        let (preview, _) = try XCTUnwrap(StampRenderer.separateInformationImage(snapshot: snapshot, address: content.address, size: CGSize(width: 400, height: 600), displayScale: 3))
        XCTAssertEqual(preview.scale, 3)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(preview.cgImage).width, Int(preview.size.width * 3) - 1)
        let attachment = XCTAttachment(image: preview)
        attachment.name = "separate-information-example"
        attachment.lifetime = .keepAlways
        add(attachment)
        let unavailable = StampSnapshot(capturedAt: date, gpsEnabled: false, location: nil, heading: nil, layout: layout)
            .separateInformation(address: "Não deve aparecer")
        XCTAssertNil(unavailable.address)
        XCTAssertNil(unavailable.coordinate)
        XCTAssertNil(unavailable.weather)
    }

    func testFixedFontFitsClockAndDateWithoutTruncation() {
        let clock = StampRenderer.fittedFixedFont(UIFont.monospacedDigitSystemFont(ofSize: 70, weight: .medium), sample: "88:88", width: 120)
        let date = StampRenderer.fittedFixedFont(UIFont.systemFont(ofSize: 30), sample: "88/88/8888", width: 100)
        XCTAssertLessThanOrEqual(("88:88" as NSString).size(withAttributes: [.font: clock]).width, 120)
        XCTAssertLessThanOrEqual(("88/88/8888" as NSString).size(withAttributes: [.font: date]).width, 100)
        let sample = "88.88888°S, 188.88888°O"
        let coordinates = StampRenderer.fittedFixedFont(UIFont.systemFont(ofSize: 24), sample: sample, width: 160)
        XCTAssertLessThanOrEqual((sample as NSString).size(withAttributes: [.font: coordinates]).width, 160)
    }
    func testMapLoadingOnlyRunsForTemplatesThatUseMap() {
        var layout = StampLayout()
        layout.template = .workReport
        let report = StampSnapshot(capturedAt: Date(), gpsEnabled: true, mapEnabled: true, location: nil, heading: nil, layout: layout)
        XCTAssertFalse(report.mapEnabled)
        layout.template = .map
        let mapped = StampSnapshot(capturedAt: Date(), gpsEnabled: true, mapEnabled: true, location: nil, heading: nil, layout: layout)
        XCTAssertTrue(mapped.mapEnabled)
        let disabled = StampSnapshot(capturedAt: Date(), gpsEnabled: false, mapEnabled: true, location: nil, heading: nil, layout: layout)
        XCTAssertFalse(disabled.mapEnabled)
    }
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

    func testFixedTemplatesKeepDifferentVisualDesigns() throws {
        func render(_ template: StampLayout.Template) throws -> Data {
            var layout = StampLayout()
            layout.template = template
            let snapshot = StampSnapshot(capturedAt: Date(timeIntervalSince1970: 1_760_000_000),
                                         gpsEnabled: false, location: nil, heading: nil, layout: layout)
            let image = try XCTUnwrap(StampRenderer.overlay(size: CGSize(width: 400, height: 600), snapshot: snapshot, map: nil, address: nil))
            return try XCTUnwrap(image.pngData())
        }
        let report = try render(.workReport)
        let spreadsheet = try render(.spreadsheet)
        let inspection = try render(.inspection)
        XCTAssertNotEqual(report, spreadsheet)
        XCTAssertNotEqual(spreadsheet, inspection)
    }

    func testExportFixedTemplatePreviewsForVisualReview() throws {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40.7812, longitude: -73.9665),
                                  altitude: 30, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: date)
        let map = UIImage(named: "StampSampleMap", in: Bundle(for: StampProfilesStore.self), compatibleWith: nil)
        let logos = [UIColor.systemRed, .systemBlue, .systemGreen].map { color in
            UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
                color.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 8, y: 8, width: 48, height: 48))
            }
        }
        let forecast = Forecast(validAt: date, updatedAt: date, temperatureC: 22, humidityPercent: 60,
                                windMetersPerSecond: 2, seaLevelPressureHpa: 1012)
        for template in StampLayout.Template.allCases where template.hasFixedRenderer {
            var layout = StampLayout()
            layout.template = template
            for field in template.fields { layout.setTemplateValue(field + " exemplo", for: field) }
            let snapshot = StampSnapshot(capturedAt: date, gpsEnabled: true, mapEnabled: true, addressEnabled: true,
                                         logo: logos[0], extraLogos: [logos[1], logos[2]], forecast: forecast,
                                         location: location, heading: nil, layout: layout)
            let image = try XCTUnwrap(StampRenderer.overlay(size: CGSize(width: 400, height: 600), snapshot: snapshot,
                                                             map: map, address: "Central Park, Nova York"))
            let preview = UIGraphicsImageRenderer(size: image.size).image { context in
                UIColor.darkGray.setFill()
                context.fill(CGRect(origin: .zero, size: image.size))
                image.draw(at: .zero)
            }
            let attachment = XCTAttachment(image: preview)
            attachment.name = "stamp-\(template.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
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

    func testFixedTemplateCoordinatesIncludeCorrectHemispheres() {
        let now = Date()
        let point = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -17.9, longitude: -51.7),
                               altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: now)
        let snapshot = StampSnapshot(capturedAt: now, gpsEnabled: true, location: point, heading: nil)
        let coordinate = snapshot.templateContent(address: nil).coordinate
        XCTAssertEqual(coordinate, "17.90000°S, 51.70000°O")
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
