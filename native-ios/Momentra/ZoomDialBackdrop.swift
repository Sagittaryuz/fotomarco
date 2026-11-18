import SwiftUI

struct ZoomDialBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            let radius = geometry.size.width * 0.63
            let center = CGPoint(x: geometry.size.width / 2, y: radius + 8)
            let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ZStack {
                Path(ellipseIn: disc).fill(.ultraThinMaterial)
                Path(ellipseIn: disc).fill(.black.opacity(0.65))
            }
            .blur(radius: 1)
            .mask(
                LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.9), location: 0.72),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
