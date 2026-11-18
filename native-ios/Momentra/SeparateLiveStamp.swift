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
                    let side = unit * (snapshot.mapScale == "small" ? 0.14 : snapshot.mapScale == "large" ? 0.27 : 0.20)
                    let rect = StampRenderer.positionedRect(size: size, element: CGSize(width: side, height: side),
                                                           centre: layout.map, margin: margin)
                    Map(position: .constant(.region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 350, longitudinalMeters: 350))), interactionModes: []) {
                        Annotation("Localização", coordinate: coordinate) {
                            Circle().fill(.blue).frame(width: 11, height: 11).overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    .mapStyle(.imagery)
                    .frame(width: side, height: side)
                    .position(x: rect.midX, y: rect.midY)
                    .id("\(Int(coordinate.latitude * 1000))-\(Int(coordinate.longitude * 1000))")
                }
                if layout.showsInformation {
                    let lines = (snapshot.addressEnabled && snapshot.location != nil ? [snapshot.cachedAddress ?? "Buscando endereço…"] : []) + snapshot.lines
                    Text(lines.joined(separator: "\n"))
                        .font(.system(size: max(8, unit * (snapshot.compact ? 0.021 : 0.027)), weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(layout.information.x >= 0.5 ? .trailing : .leading)
                        .shadow(color: .black, radius: 2, x: 1, y: 1)
                        .frame(width: size.width * 0.60, alignment: layout.information.x >= 0.5 ? .trailing : .leading)
                        .position(x: min(max(size.width * 0.30 + margin, CGFloat(layout.information.x) * size.width), size.width * 0.70 - margin),
                                  y: min(max(margin + 35, CGFloat(layout.information.y) * size.height), size.height - margin - 35))
                }
                if layout.showsLogo, let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
                    let factor = min(unit * 0.15 / logo.size.width, unit * 0.15 / logo.size.height)
                    let logoSize = CGSize(width: logo.size.width * factor, height: logo.size.height * factor)
                    let rect = StampRenderer.positionedRect(size: size, element: logoSize, centre: layout.logo, margin: margin)
                    Image(uiImage: logo).resizable().scaledToFit().frame(width: logoSize.width, height: logoSize.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }.frame(width: size.width, height: size.height)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
