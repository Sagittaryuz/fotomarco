import Foundation

/// Positions identify an anchor on the image; elements grow inward from it.
struct StampPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }

    func sharesCorner(with other: StampPoint) -> Bool {
        (x < 0.5) == (other.x < 0.5) && (y < 0.5) == (other.y < 0.5)
    }
}

struct StampLayout: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable { case combined, separate }
    enum MapAppearance: String, Codable, CaseIterable { case map, satellite }
    enum Template: String, Codable, CaseIterable, Identifiable {
        case original, locationWeather, spreadsheet, workReport, visit, clean, largeMap
        case timeLocation, custom, map, patrol, checkIn, construction
        case completed, portrait, delivery, inspection, shopee, deliveryProof
        var id: String { rawValue }
        var title: String {
            switch self {
            case .original: "Atual"
            case .locationWeather: "Localização e clima"
            case .spreadsheet: "Planilha"
            case .workReport: "Relatório de trabalho"
            case .visit: "Registro de visita"
            case .clean: "Limpo"
            case .largeMap: "Mapa grande"
            case .timeLocation: "Hora e localização"
            case .custom: "Personalizado"
            case .map: "Mapa"
            case .patrol: "Patrulha"
            case .checkIn: "Registrar entrada"
            case .construction: "Construção"
            case .completed: "Concluído"
            case .portrait: "Retrato"
            case .delivery: "Entrega"
            case .inspection: "Inspeção"
            case .shopee: "Shopee"
            case .deliveryProof: "Prova de entrega"
            }
        }
        var fields: [String] {
            switch self {
            case .spreadsheet: ["Título"]
            case .workReport: ["Projeto", "Inspeção"]
            case .visit: ["Título"]
            case .clean: ["Texto"]
            case .custom: ["Título"]
            case .patrol: ["Título"]
            case .checkIn: ["Título"]
            case .construction: ["Título", "Descrição"]
            case .portrait: ["Nome"]
            case .delivery: ["Veículo", "Encomenda"]
            case .inspection: ["Título"]
            case .shopee: ["Código", "Previsão de entrega"]
            case .original, .locationWeather, .largeMap, .timeLocation, .map, .completed, .deliveryProof: []
            }
        }
        var usesMap: Bool { [.visit, .largeMap, .map, .delivery].contains(self) }
        var usesLogo: Bool { [.construction, .completed, .portrait, .shopee, .deliveryProof].contains(self) }
        var hasFixedRenderer: Bool { [.workReport, .spreadsheet, .locationWeather, .timeLocation, .custom, .map, .largeMap, .visit, .delivery, .clean, .checkIn, .patrol, .completed, .deliveryProof, .inspection, .portrait, .shopee, .construction].contains(self) }
    }
    var mode: Mode = .combined
    var showsMap = true
    var showsInformation = true
    var showsLogo = true
    var showsLocationQR = false
    var locationQRSize: Double = 1
    var locationQR = StampPoint(x: 0.15, y: 0.90)
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
    var template: Template = .original
    var templateValues: [String: [String: String]] = [:]
    mutating func selectTemplate(_ next: Template) {
        guard next != template else { return }
        templateValues[template.rawValue, default: [:]]["_mapStyle"] = mapStyle.rawValue
        templateValues[template.rawValue, default: [:]]["_showsMap"] = showsMap ? "1" : "0"
        template = next
        if let saved = templateValues[next.rawValue] {
            mapStyle = saved["_mapStyle"].flatMap(MapAppearance.init(rawValue:)) ?? .map
            showsMap = saved["_showsMap"].map { $0 == "1" } ?? true
        } else {
            mapStyle = .map
            showsMap = true
        }
    }
    /// The locked camera only needs values for the currently selected template.
    func lockedCaptureLayout() -> StampLayout {
        var result = self
        result.templateValues = templateValues[template.rawValue].map { [template.rawValue: $0] } ?? [:]
        result.templateValues[template.rawValue]?.removeValue(forKey: "_image")
        result.templateValues[template.rawValue]?.removeValue(forKey: "_image2")
        result.templateValues[template.rawValue]?.removeValue(forKey: "_image3")
        return result
    }
    func templateValue(_ field: String, fallback: String = "") -> String {
        templateValues[template.rawValue]?[field] ?? fallback
    }

    mutating func setTemplateValue(_ value: String, for field: String) {
        guard template.fields.contains(field) else { return }
        var fields = templateValues[template.rawValue] ?? [:]
        let singleLine = value.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
        fields[field] = String(singleLine.prefix(96))
        templateValues[template.rawValue] = fields
    }
    var map = StampPoint(x: 0.15, y: 0.13)
    var information = StampPoint(x: 0.72, y: 0.16)
    var logo = StampPoint(x: 0.85, y: 0.90)

    init() {}

    private enum CodingKeys: String, CodingKey {
        case mode, showsMap, showsInformation, showsLogo, mapStyle, mapSize, informationSize, logoSize, combinedSize
        case fontStyle, dateFormat, textAlignment, position, horizontal, mapScale, mapCorner, logoCorner, compact, showsAddress
        case map, information, logo, showsForecast, template, templateValues
        case showsLocationQR, locationQRSize, locationQR
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decodeIfPresent(Mode.self, forKey: .mode) ?? .combined
        showsMap = try values.decodeIfPresent(Bool.self, forKey: .showsMap) ?? true
        showsInformation = try values.decodeIfPresent(Bool.self, forKey: .showsInformation) ?? true
        showsLogo = try values.decodeIfPresent(Bool.self, forKey: .showsLogo) ?? true
        showsLocationQR = try values.decodeIfPresent(Bool.self, forKey: .showsLocationQR) ?? false
        locationQR = try values.decodeIfPresent(StampPoint.self, forKey: .locationQR) ?? StampPoint(x: 0.15, y: 0.90)
        mapStyle = try values.decodeIfPresent(MapAppearance.self, forKey: .mapStyle) ?? .map
        func scale(_ key: CodingKeys) throws -> Double {
            let value = try values.decodeIfPresent(Double.self, forKey: key) ?? 1
            return value.isFinite ? min(2, max(0.5, value)) : 1
        }
        mapSize = try scale(.mapSize)
        informationSize = try scale(.informationSize)
        logoSize = try scale(.logoSize)
        combinedSize = try scale(.combinedSize)
        locationQRSize = try scale(.locationQRSize)
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
        template = (try? values.decodeIfPresent(Template.self, forKey: .template)) ?? .original
        templateValues = (try? values.decodeIfPresent([String: [String: String]].self, forKey: .templateValues)) ?? [:]
        map = try values.decodeIfPresent(StampPoint.self, forKey: .map) ?? StampPoint(x: 0.15, y: 0.13)
        information = try values.decodeIfPresent(StampPoint.self, forKey: .information) ?? StampPoint(x: 0.72, y: 0.16)
        logo = try values.decodeIfPresent(StampPoint.self, forKey: .logo) ?? StampPoint(x: 0.85, y: 0.90)
    }
}
