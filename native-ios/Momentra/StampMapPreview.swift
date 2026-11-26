import MapKit
import SwiftUI

struct MomentraLocationMarker: View {
    var size: CGFloat

    var body: some View {
        Circle().fill(Color.yellow)
            .overlay(Circle().stroke(.white, lineWidth: max(1, size * 0.10)))
            .overlay {
                Image(systemName: "location.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.black)
                    .padding(size * 0.24)
            }
            .frame(width: size, height: size)
    }
}

/// Uses the same complete MapKit image as the photo carimbo.
struct StampMapPreview: View {
    let snapshot: StampSnapshot
    let markerSize: CGFloat
    var fillsFrame = false
    @State private var image: UIImage?
    private static let queue = DispatchQueue(label: "br.com.momentra.stamp-map-preview", qos: .utility)

    private var key: String {
        guard let point = snapshot.location?.coordinate else { return "" }
        return "\(Int(point.latitude * 1000)):\(Int(point.longitude * 1000)):\(snapshot.layout.mapStyle.rawValue)"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    if fillsFrame {
                        Image(uiImage: image).resizable().frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    }
                    MomentraLocationMarker(size: markerSize)
                } else {
                    ProgressView().controlSize(.small)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
                .overlay { Rectangle().strokeBorder(.white, lineWidth: max(1, min(proxy.size.width, proxy.size.height) * 0.012)) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: key) {
            image = nil
            let result: UIImage? = await withCheckedContinuation { continuation in
                Self.queue.async {
                    StampMap.load(snapshot: snapshot, queue: Self.queue) { continuation.resume(returning: $0) }
                }
            }
            if !Task.isCancelled { image = result }
        }
    }
}
