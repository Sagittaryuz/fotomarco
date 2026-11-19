import Foundation

/// Positions identify an anchor on the image; elements grow inward from it.
struct StampPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }
}

struct StampLayout: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable { case combined, separate }
    enum MapAppearance: String, Codable, CaseIterable { case map, satellite }
    var mode: Mode = .combined
    var showsMap = true
    var showsInformation = true
    var showsLogo = true
    var mapStyle: MapAppearance = .map
    var mapSize: Double = 1
    var informationSize: Double = 1
    var logoSize: Double = 1
    var combinedSize: Double = 1
    var fontStyle = "system"
    var dateFormat = "numeric"
    var textAlignment = "auto"
    var position = "bottom"
    var horizontal = "auto"
    var mapScale = "medium"
    var mapCorner = "auto"
    var logoCorner = "auto"
    var compact = false
    var showsAddress = true
    var showsForecast = true
    var map = StampPoint(x: 0.15, y: 0.13)
    var information = StampPoint(x: 0.72, y: 0.16)
    var logo = StampPoint(x: 0.85, y: 0.90)

    init() {}

    private enum CodingKeys: String, CodingKey {
        case mode, showsMap, showsInformation, showsLogo, mapStyle, mapSize, informationSize, logoSize, combinedSize
        case fontStyle, dateFormat, textAlignment, position, horizontal, mapScale, mapCorner, logoCorner, compact, showsAddress
        case map, information, logo, showsForecast
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decodeIfPresent(Mode.self, forKey: .mode) ?? .combined
        showsMap = try values.decodeIfPresent(Bool.self, forKey: .showsMap) ?? true
        showsInformation = try values.decodeIfPresent(Bool.self, forKey: .showsInformation) ?? true
        showsLogo = try values.decodeIfPresent(Bool.self, forKey: .showsLogo) ?? true
        mapStyle = try values.decodeIfPresent(MapAppearance.self, forKey: .mapStyle) ?? .map
        func scale(_ key: CodingKeys) throws -> Double {
            let value = try values.decodeIfPresent(Double.self, forKey: key) ?? 1
            return value.isFinite ? min(2, max(0.5, value)) : 1
        }
        mapSize = try scale(.mapSize)
        informationSize = try scale(.informationSize)
        logoSize = try scale(.logoSize)
        combinedSize = try scale(.combinedSize)
        func choice(_ key: CodingKeys, allowed: [String], fallback: String) throws -> String {
            let value = try values.decodeIfPresent(String.self, forKey: key) ?? fallback
            return allowed.contains(value) ? value : fallback
        }
        fontStyle = try choice(.fontStyle, allowed: ["system", "serif", "mono"], fallback: "system")
        dateFormat = try choice(.dateFormat, allowed: ["numeric", "long"], fallback: "numeric")
        textAlignment = try choice(.textAlignment, allowed: ["auto", "left", "center", "right"], fallback: "auto")
        position = try choice(.position, allowed: ["top", "bottom"], fallback: "bottom")
        horizontal = try choice(.horizontal, allowed: ["auto", "left", "right"], fallback: "auto")
        mapScale = try choice(.mapScale, allowed: ["small", "medium", "large"], fallback: "medium")
        let corners = ["auto", "top-left", "top-right", "bottom-left", "bottom-right"]
        mapCorner = try choice(.mapCorner, allowed: corners, fallback: "auto")
        logoCorner = try choice(.logoCorner, allowed: corners, fallback: "auto")
        compact = try values.decodeIfPresent(Bool.self, forKey: .compact) ?? false
        showsAddress = try values.decodeIfPresent(Bool.self, forKey: .showsAddress) ?? true
        showsForecast = try values.decodeIfPresent(Bool.self, forKey: .showsForecast) ?? true
        map = try values.decodeIfPresent(StampPoint.self, forKey: .map) ?? StampPoint(x: 0.15, y: 0.13)
        information = try values.decodeIfPresent(StampPoint.self, forKey: .information) ?? StampPoint(x: 0.72, y: 0.16)
        logo = try values.decodeIfPresent(StampPoint.self, forKey: .logo) ?? StampPoint(x: 0.85, y: 0.90)
    }
}
