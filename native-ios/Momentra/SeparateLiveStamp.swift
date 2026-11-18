import SwiftUI
import MapKit

struct SeparateLiveStamp: View {
    let snapshot: StampSnapshot

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, size.height)
            let margin = unit * 0.025
            let layout = snapshot.layout
            ZStack {
                if layout.showsMap, snapshot.mapEnabled, let coordinate = snapshot.location?.coordinate {
                    let side = min(unit * 0.5, unit * (snapshot.mapScale == "small" ? 0.14 : snapshot.mapScale == "large" ? 0.27 : 0.20) * CGFloat(layout.mapSize))
                    let rect = StampRenderer.positionedRect(size: size, element: CGSize(width: side, height: side),
                                                           centre: layout.map, margin: margin)
                    Map(position: .constant(.region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350))), interactionModes: []) {
                        Annotation("Localização", coordinate: coordinate) {
                            Circle().fill(.blue).frame(width: 11, height: 11).overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    .mapStyle(layout.mapStyle == .satellite ? .imagery : .standard)
                    .frame(width: side, height: side)
                    .position(x: rect.midX, y: rect.midY)
                    .id("\(Int(coordinate.latitude * 1000))-\(Int(coordinate.longitude * 1000))")
                }
                if layout.showsInformation {
                    let lines = (snapshot.addressEnabled && snapshot.location != nil ? [snapshot.cachedAddress ?? "Buscando endereço…"] : []) + snapshot.lines
                    Text(lines.joined(separator: "\n"))
                        .font(.system(size: max(8, unit * (snapshot.compact ? 0.021 : 0.027) * CGFloat(layout.informationSize)), weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(textAlignment(layout))
                        .shadow(color: .black, radius: 2, x: 1, y: 1)
                        .frame(width: min(size.width - margin * 2, size.width * 0.60 * CGFloat(max(1, layout.informationSize))), alignment: layout.information.x >= 0.5 ? .trailing : .leading)
                        .position(x: min(max(size.width * 0.30 + margin, CGFloat(layout.information.x) * size.width), size.width * 0.70 - margin),
                                  y: min(max(margin + 35, CGFloat(layout.information.y) * size.height), size.height - margin - 35))
                }
                if layout.showsLogo, let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
                    let maxSide = min(unit * 0.35, unit * 0.15 * CGFloat(layout.logoSize))
                    let factor = min(maxSide / logo.size.width, maxSide / logo.size.height)
                    let logoSize = CGSize(width: logo.size.width * factor, height: logo.size.height * factor)
                    let rect = StampRenderer.positionedRect(size: size, element: logoSize, centre: layout.logo, margin: margin)
                    Image(uiImage: logo).resizable().scaledToFit().frame(width: logoSize.width, height: logoSize.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }.frame(width: size.width, height: size.height)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private func textAlignment(_ layout: StampLayout) -> TextAlignment {
        switch layout.textAlignment {
        case "left": return .leading
        case "center": return .center
        case "right": return .trailing
        default: return layout.information.x >= 0.5 ? .trailing : .leading
        }
    }
}
