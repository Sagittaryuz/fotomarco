import SwiftUI
import MapKit

struct SeparateLiveStamp: View {
    let snapshot: StampSnapshot
    var editMap: () -> Void = {}
    var editInformation: () -> Void = {}
    var editLogo: () -> Void = {}
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, size.height)
            let margin = unit * 0.025
            let layout = snapshot.layout
            ZStack {
                if layout.showsMap, snapshot.mapEnabled, snapshot.location != nil {
                    let space = StampRenderer.availableSize(size: size, anchor: layout.map, margin: margin)
                    let side = min(space.width, space.height, unit * 0.5, unit * (snapshot.mapScale == "small" ? 0.14 : snapshot.mapScale == "large" ? 0.27 : 0.20) * CGFloat(layout.mapSize))
                    let rect = StampRenderer.positionedRect(size: size, element: CGSize(width: side, height: side),
                                                           centre: layout.map, margin: margin)
                    StampMapPreview(snapshot: snapshot, markerSize: 11)
                    .frame(width: side, height: side)
                    .overlay { Color.clear.contentShape(Rectangle()).onTapGesture(perform: editMap) }
                    .position(x: rect.midX, y: rect.midY)
                }
                if layout.showsInformation {
                    if let (image, rect) = StampRenderer.separateInformationImage(snapshot: snapshot, address: snapshot.cachedAddress, size: size, displayScale: displayScale) {
                        Image(uiImage: image).resizable()
                            .frame(width: rect.width, height: rect.height)
                            .contentShape(Rectangle()).onTapGesture(perform: editInformation)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                if layout.showsLogo, let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
                    let space = StampRenderer.availableSize(size: size, anchor: layout.logo, margin: margin)
                    let maxSide = min(space.width, space.height, unit * 0.35, unit * 0.15 * CGFloat(layout.logoSize))
                    let factor = min(maxSide / logo.size.width, maxSide / logo.size.height)
                    let logoSize = CGSize(width: logo.size.width * factor, height: logo.size.height * factor)
                    let rect = StampRenderer.positionedRect(size: size, element: logoSize, centre: layout.logo, margin: margin)
                    Image(uiImage: logo).resizable().scaledToFit().frame(width: logoSize.width, height: logoSize.height)
                        .contentShape(Rectangle()).onTapGesture(perform: editLogo)
                        .accessibilityLabel("Editar logotipo")
                        .position(x: rect.midX, y: rect.midY)
                }
            }.frame(width: size.width, height: size.height)
        }
    }
}
