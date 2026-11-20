import SwiftUI
import MapKit

struct SeparateLiveStamp: View {
    let snapshot: StampSnapshot
    var editMap: () -> Void = {}
    var editInformation: () -> Void = {}

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
                    let lines = snapshot.informationLines(address: snapshot.addressEnabled && snapshot.location != nil ? snapshot.cachedAddress ?? "Buscando endereço…" : nil)
                    let space = StampRenderer.availableSize(size: size, anchor: layout.information, margin: margin)
                    let width = min(space.width, size.width * 0.60 * CGFloat(max(1, layout.informationSize)))
                    let paragraph: NSMutableParagraphStyle = {
                        let value = NSMutableParagraphStyle()
                        value.lineBreakMode = .byTruncatingTail
                        return value
                    }()
                    let measured = StampRenderer.fitText(lines.joined(separator: "\n") as NSString, width: width,
                        maxHeight: space.height, initialSize: max(8, unit * (snapshot.compact ? 0.021 : 0.027) * CGFloat(layout.informationSize)),
                        style: snapshot.fontStyle, paragraph: paragraph)
                    let rect = StampRenderer.positionedRect(size: size, element: CGSize(width: width, height: measured?.height ?? 0), centre: layout.information, margin: margin)
                    Text(lines.joined(separator: "\n"))
                        .lineLimit(5)
                        .font(.system(size: measured?.font.pointSize ?? 8, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(textAlignment(layout))
                        .shadow(color: .black, radius: 2, x: 1, y: 1)
                        .frame(width: rect.width, height: rect.height, alignment: layout.information.x >= 0.5 ? .topTrailing : .topLeading)
                        .onTapGesture(perform: editInformation)
                        .position(x: rect.midX, y: rect.midY)
                }
                if layout.showsLogo, let logo = snapshot.logo, logo.size.width > 0, logo.size.height > 0 {
                    let space = StampRenderer.availableSize(size: size, anchor: layout.logo, margin: margin)
                    let maxSide = min(space.width, space.height, unit * 0.35, unit * 0.15 * CGFloat(layout.logoSize))
                    let factor = min(maxSide / logo.size.width, maxSide / logo.size.height)
                    let logoSize = CGSize(width: logo.size.width * factor, height: logo.size.height * factor)
                    let rect = StampRenderer.positionedRect(size: size, element: logoSize, centre: layout.logo, margin: margin)
                    Image(uiImage: logo).resizable().scaledToFit().frame(width: logoSize.width, height: logoSize.height)
                        .onTapGesture(perform: editInformation)
                        .position(x: rect.midX, y: rect.midY)
                }
            }.frame(width: size.width, height: size.height)
        }
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
