import Foundation

/// Positions are normalized to the image and represent each element's centre.
struct StampPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }
}

struct StampLayout: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable {
        case combined, separate
    }
    var mode: Mode = .combined
    var showsMap = true
    var showsInformation = true
    var showsLogo = true
    var map = StampPoint(x: 0.15, y: 0.13)
    var information = StampPoint(x: 0.72, y: 0.16)
    var logo = StampPoint(x: 0.85, y: 0.90)
}
