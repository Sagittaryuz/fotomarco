import SwiftUI

struct CameraZoomStrip: View {
    let presets: [CGFloat]
    let zoom: CGFloat
    let shutterCenterX: CGFloat?
    let select: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let selectedIndex = CameraZoomSelection.index(for: zoom, presets: presets) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let origin = geometry.frame(in: .named("MomentraCamera")).minX
                let center = shutterCenterX.map { $0 - origin } ?? width / 2
                let mirroredWidth = 2 * min(center, width - center)
                let step = min(44, max(0, mirroredWidth) / CGFloat(presets.count * 2 - 1))
                let offset = (CGFloat(presets.count - 1) / 2 - CGFloat(selectedIndex)) * step
                HStack(spacing: 0) {
                    ForEach(presets.indices, id: \.self) { index in
                        let preset = presets[index]
                        let selected = index == selectedIndex
                        let label = CameraZoomSelection.label(selected ? zoom : preset)
                        Button { select(preset) } label: {
                            zoomLabel(selected ? label + "×" : label, selected: selected, width: step)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Zoom \(preset == 0.5 ? "meio" : CameraZoomSelection.label(preset)) vezes")
                        .accessibilityValue(selected ? label + "×" : "")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .position(x: center + offset, y: 22)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selectedIndex)
            }
            .frame(height: 44)
        }
    }

    @ViewBuilder private func zoomLabel(_ text: String, selected: Bool, width: CGFloat) -> some View {
        let label = Text(text)
            .font(.subheadline.weight(.medium)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.65)
            .frame(width: width, height: 44)
            .contentShape(Rectangle())
        label
            .foregroundStyle(selected ? Color.yellow : Color.white)
            .background(selected ? Color.black.opacity(0.58) : .clear, in: Circle())
    }
}
