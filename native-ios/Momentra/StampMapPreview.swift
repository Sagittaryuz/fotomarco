import MapKit
import SwiftUI

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
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fillsFrame ? .fill : .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                    Circle().fill(.blue).frame(width: markerSize, height: markerSize)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                } else {
                    ProgressView().controlSize(.small)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
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
