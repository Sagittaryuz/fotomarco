import SwiftUI

struct GalleryPhotoViewport<Photo: View>: View {
    let active: Bool
    @Binding var controlsHidden: Bool
    @Binding var zoomed: Bool
    @ViewBuilder let photo: () -> Photo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var pinchStart: CGFloat?
    @State private var anchor: UnitPoint = .center
    @State private var offset: CGSize = .zero
    @GestureState private var drag = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                photo()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale, anchor: anchor)
                    .offset(bounded(CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
                                    in: proxy.size))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(taps(in: proxy.size), including: active ? .all : .none)
            .simultaneousGesture(pinch, including: active ? .all : .none)
            .highPriorityGesture(pan(in: proxy.size), including: active && scale > 1 ? .all : .none)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Foto")
            .accessibilityIdentifier("gallery-photo-viewport")
            .accessibilityValue(scale > 1 ? "Ampliada" : "Tamanho normal")
            .accessibilityAction(named: controlsHidden ? "Mostrar controles" : "Ocultar controles") {
                toggleControls()
            }
            .accessibilityAction(named: scale > 1 ? "Restaurar zoom" : "Ampliar foto") {
                doubleTap(at: .center)
            }
        }
        .onChange(of: active) { _, visible in
            if !visible { reset() }
        }
    }

    private func taps(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2).exclusively(before: SpatialTapGesture())
            .onEnded { value in
                switch value {
                case .first(let tap):
                    let point = UnitPoint(x: min(1, max(0, tap.location.x / max(1, size.width))),
                                          y: min(1, max(0, tap.location.y / max(1, size.height))))
                    doubleTap(at: point)
                case .second:
                    toggleControls()
                }
            }
    }

    private func toggleControls() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            let showControls = controlsHidden
            controlsHidden.toggle()
            if showControls { reset(); zoomed = false }
        }
    }

    private func doubleTap(at point: UnitPoint) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            controlsHidden = true
            if scale > 1 {
                reset()
                zoomed = false
            } else {
                anchor = point
                scale = 2.6
                zoomed = true
            }
        }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStart == nil {
                    pinchStart = scale
                    if scale == 1 { anchor = value.startAnchor }
                }
                scale = min(5, max(1, (pinchStart ?? scale) * value.magnification))
                zoomed = scale > 1
            }
            .onEnded { _ in
                pinchStart = nil
                if scale <= 1.02 { reset(); zoomed = false }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset = bounded(CGSize(width: offset.width + value.translation.width,
                                        height: offset.height + value.translation.height), in: size)
            }
    }

    private func bounded(_ translation: CGSize, in size: CGSize) -> CGSize {
        let horizontal = size.width * max(0, scale - 1)
        let vertical = size.height * max(0, scale - 1)
        return CGSize(width: min(horizontal * anchor.x, max(-horizontal * (1 - anchor.x), translation.width)),
                      height: min(vertical * anchor.y, max(-vertical * (1 - anchor.y), translation.height)))
    }

    private func reset() {
        scale = 1
        anchor = .center
        offset = .zero
        pinchStart = nil
    }
}
