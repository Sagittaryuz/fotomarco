import XCTest
import CoreLocation
@testable import Momentra

final class ForecastModelTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-16T20:30:00Z")!

    private func payload(updated: String = "2026-11-16T19:00:00Z", unit: String = "celsius") throws -> Data {
        let properties: [String: Any] = [
            "meta": ["updated_at": updated, "units": ["air_temperature": unit, "relative_humidity": "%"]],
            "timeseries": [
                ["time": "2026-11-16T21:00:00Z", "data": ["instant": ["details": ["air_temperature": 23]]]],
                ["time": "2026-11-16T20:00:00Z", "data": ["instant": ["details": ["air_temperature": 22, "relative_humidity": 91]]]]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: ["properties": properties])
    }

    func testPastModelAndUnitsOnly() throws {
        let sample = try XCTUnwrap(ForecastModel.parse(payload(), at: now))
        XCTAssertEqual(sample.temperatureC, 22)
        XCTAssertEqual(sample.humidityPercent, 91)
        XCTAssertNil(ForecastModel.parse(try payload(updated: "2026-11-16T21:00:00Z"), at: now))
        XCTAssertNil(ForecastModel.parse(try payload(), at: now.addingTimeInterval(4 * 3600)))
        XCTAssertNil(ForecastModel.parse(try payload(unit: "kelvin"), at: now)?.temperatureC)
    }

    func testCoordinatesAreTruncatedAndInvalidCoordinatesRejected() {
        XCTAssertEqual(ForecastModel.coordinateKey(CLLocationCoordinate2D(latitude: -17.123456, longitude: -51.987654)), "-17.1234,-51.9876")
        XCTAssertNil(ForecastModel.coordinateKey(CLLocationCoordinate2D(latitude: 91, longitude: 0)))
    }

    func testHourlyRainRequiresValidPeriodUnitAndValue() throws {
        func payload(rain: Double, unit: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["properties": [
                "meta": ["updated_at": "2026-11-16T19:00:00Z", "units": ["air_temperature": "celsius", "precipitation_amount": unit]],
                "timeseries": [["time": "2026-11-16T20:00:00Z", "data": [
                    "instant": ["details": ["air_temperature": 22]],
                    "next_1_hours": ["details": ["precipitation_amount": rain]]]]]]])
        }
        XCTAssertEqual(ForecastModel.parse(try payload(rain: 1.2, unit: "mm"), at: now)?.precipitationMM, 1.2)
        XCTAssertNil(ForecastModel.parse(try payload(rain: 1.2, unit: "mm"), at: now.addingTimeInterval(1800))?.precipitationMM)
        XCTAssertNil(ForecastModel.parse(try payload(rain: 1.2, unit: "cm"), at: now)?.precipitationMM)
        XCTAssertNil(ForecastModel.parse(try payload(rain: -1, unit: "mm"), at: now)?.precipitationMM)
    }
}
