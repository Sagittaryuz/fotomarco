import Foundation
import CoreLocation

struct Forecast: Codable, Equatable {
    let validAt: Date
    let updatedAt: Date
    let temperatureC: Double?
    let humidityPercent: Double?
    let windMetersPerSecond: Double?
    let seaLevelPressureHpa: Double?
    var precipitationMM: Double? = nil

    func isValid(at date: Date) -> Bool {
        validAt <= date && updatedAt <= date && date.timeIntervalSince(validAt) <= 7200 && date.timeIntervalSince(updatedAt) <= 86400
    }
}

enum ForecastModel {
    private struct Response: Decodable {
        struct Properties: Decodable {
            struct Meta: Decodable {
                let updated_at: String
                let units: [String: String]
            }
            struct Entry: Decodable {
                struct DataValue: Decodable {
                    struct Instant: Decodable { let details: [String: Double] }
                    struct Period: Decodable { let details: [String: Double] }
                    let instant: Instant
                    let next_1_hours: Period?
                }
                let time: String
                let data: DataValue
            }
            let meta: Meta
            let timeseries: [Entry]
        }
        let properties: Properties
    }

    static func coordinateKey(_ coordinate: CLLocationCoordinate2D) -> String? {
        guard CLLocationCoordinate2DIsValid(coordinate), coordinate.latitude.isFinite, coordinate.longitude.isFinite else { return nil }
        let lat = (coordinate.latitude * 10000).rounded(.towardZero) / 10000
        let lon = (coordinate.longitude * 10000).rounded(.towardZero) / 10000
        return String(format: "%.4f,%.4f", locale: Locale(identifier: "en_US_POSIX"), lat, lon)
    }

    static func parse(_ data: Data, at date: Date) -> Forecast? {
        guard data.count <= 1_000_000, let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let formatter = ISO8601DateFormatter()
        func parseDate(_ value: String) -> Date? {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
        guard let updated = parseDate(response.properties.meta.updated_at), updated <= date, date.timeIntervalSince(updated) <= 86400 else { return nil }
        let candidates = response.properties.timeseries.prefix(512).compactMap { entry -> (Date, [String: Double], [String: Double]?)? in
            guard let time = parseDate(entry.time), time <= date, date.timeIntervalSince(time) <= 7200 else { return nil }
            return (time, entry.data.instant.details, entry.data.next_1_hours?.details)
        }
        guard let selected = candidates.max(by: { $0.0 < $1.0 }) else { return nil }
        let units = response.properties.meta.units
        func field(_ key: String, unit: String, range: ClosedRange<Double>) -> Double? {
            guard units[key] == unit, let value = selected.1[key], value.isFinite, range.contains(value) else { return nil }
            return value
        }
        let rain = selected.2?["precipitation_amount"]
        let validRain = units["precipitation_amount"] == "mm" && date.timeIntervalSince(selected.0) < 3600 &&
            rain?.isFinite == true && (0...500).contains(rain ?? -1) ? rain : nil
        let result = Forecast(validAt: selected.0, updatedAt: updated,
                              temperatureC: field("air_temperature", unit: "celsius", range: -100...70),
                              humidityPercent: field("relative_humidity", unit: "%", range: 0...100),
                              windMetersPerSecond: field("wind_speed", unit: "m/s", range: 0...150),
                              seaLevelPressureHpa: field("air_pressure_at_sea_level", unit: "hPa", range: 800...1100),
                              precipitationMM: validRain)
        guard result.temperatureC != nil || result.humidityPercent != nil || result.windMetersPerSecond != nil || result.seaLevelPressureHpa != nil else { return nil }
        return result
    }
}
