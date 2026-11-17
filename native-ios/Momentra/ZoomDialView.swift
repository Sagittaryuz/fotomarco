import SwiftUI

/// Curved zoom ruler, with zoom values expressed relative to the wide camera.
struct ZoomDialView: View {
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let presets: [CGFloat]
    let setZoom: (CGFloat) -> Void
    let dismiss: () -> Void
    @State private var dragStart: CGFloat?
    private let angularScale: CGFloat = 0.52

    var body: some View {
        Canvas { context, size in
            let radius = size.width * 0.63
            let center = CGPoint(x: size.width / 2, y: radius + 8)
            let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: disc), with: .color(.black.opacity(0.72)))
            guard value > 0 else { return }
            for index in 5...400 {
                let tick = CGFloat(index) / 10
                guard tick >= range.lowerBound - 0.02, tick <= range.upperBound + 0.02 else { continue }
                let angle = log(tick / value) * angularScale
                guard abs(angle) < 0.98 else { continue }
                let major = index % 10 == 0 || index == 5
                let length: CGFloat = major ? 19 : 11
                let outer = CGPoint(x: center.x + sin(angle) * (radius - 5), y: center.y - cos(angle) * (radius - 5))
                let inner = CGPoint(x: center.x + sin(angle) * (radius - 5 - length), y: center.y - cos(angle) * (radius - 5 - length))
                var line = Path(); line.move(to: outer); line.addLine(to: inner)
                context.stroke(line, with: .color(.white.opacity(major ? 0.8 : 0.38)), lineWidth: major ? 1.2 : 0.55)
            }
            let labelValues = Array(Set(presets + [4, 8, 40])).sorted()
            for tick in labelValues where tick >= range.lowerBound - 0.03 && tick <= range.upperBound + 0.03 {
                let angle = log(tick / value) * angularScale
                guard abs(angle) < 0.9, abs(log(tick / value)) > 0.13 else { continue }
                let point = CGPoint(x: center.x + sin(angle) * (radius - 44), y: center.y - cos(angle) * (radius - 44))
                let label = tick == 0.5 ? "0,5" : String(format: "%.0f", tick)
                context.draw(Text(label).font(.system(size: 16, weight: .medium)).foregroundColor(.white.opacity(0.8)), at: point)
            }
            var marker = Path()
            marker.move(to: CGPoint(x: center.x - 3, y: 9)); marker.addLine(to: CGPoint(x: center.x + 3, y: 9)); marker.addLine(to: CGPoint(x: center.x, y: 22)); marker.closeSubpath()
            context.fill(marker, with: .color(.yellow))
            let rounded = (value * 10).rounded() / 10
            let title = (rounded == rounded.rounded() ? String(format: "%.0f", rounded) : String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")) + "×"
            context.draw(Text(title).font(.system(size: 17, weight: .medium)).foregroundColor(.yellow), at: CGPoint(x: center.x, y: 50))
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                if dragStart == nil { dragStart = value }
                let next = (dragStart ?? value) * exp(gesture.translation.width / 150)
                setZoom(min(range.upperBound, max(range.lowerBound, next)))
            }
            .onEnded { _ in dragStart = nil })
        .onTapGesture { dismiss() }
        .accessibilityElement()
        .accessibilityLabel("Zoom da câmera")
        .accessibilityValue(String(format: "%.1f vezes", value))
        .accessibilityAdjustableAction { direction in
            let factor: CGFloat = direction == .increment ? 1.1 : 1 / 1.1
            setZoom(min(range.upperBound, max(range.lowerBound, value * factor)))
        }
        .accessibilityHint("Deslize para ajustar. Toque para fechar.")
    }
}
