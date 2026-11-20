import SwiftUI

/// Interactive glass and short directional swipes for the camera mode picker.
struct SlidingCapsule<Labels: View>: View {
    let selectedRight: Bool
    let canSelectLeft: Bool
    let canSelectRight: Bool
    let selectionChanged: (Bool) -> Void
    let height: CGFloat
    @ViewBuilder let labels: (Bool) -> Labels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @GestureState private var drag: CGFloat?
    @State private var changing = false
    @State private var changeTask: Task<Void, Never>?
    private let swipeThreshold: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 3
            let knobHeight = max(0, height - 2 * inset)
            let usable = max(0, geometry.size.width - inset * 2)
            let knob = usable / 2
            let travel = max(0, usable - knob)
            let origin = selectedRight ? travel : 0
            let offset = min(travel, max(0, origin + (drag ?? 0)))
            let proposed = drag.map { $0 > 0 } ?? selectedRight
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13))
                Group {
                    if #available(iOS 26, *) {
                        GlassEffectContainer {
                            Capsule().fill(.white.opacity(0.07))
                                .frame(width: knob, height: knobHeight)
                                .glassEffect(.regular.interactive(isEnabled && !reduceMotion), in: Capsule())
                        }
                    } else {
                        Capsule().fill(.white.opacity(0.23))
                            .frame(width: knob, height: knobHeight)
                    }
                }
                .scaleEffect(x: (drag != nil || changing) && !reduceMotion ? 1.08 : 1,
                             y: (drag != nil || changing) && !reduceMotion ? 1.15 : 1)
                .offset(x: offset + inset)
                labels(proposed)
                    .padding(.horizontal, inset)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84), value: drag != nil)
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84), value: changing)
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84), value: selectedRight)
            .contentShape(Capsule())
            .simultaneousGesture(DragGesture(minimumDistance: swipeThreshold)
                .updating($drag) { value, state, _ in
                    guard isEnabled, canSelectLeft && canSelectRight, state != nil ||
                        abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = value.translation.width
                }
                .onEnded { value in
                    let movement = value.translation
                    guard isEnabled, canSelectLeft && canSelectRight, travel > 0,
                          abs(movement.width) >= swipeThreshold,
                          abs(movement.width) > abs(movement.height) else { return }
                    let targetRight = movement.width > 0
                    if targetRight != selectedRight { selectionChanged(targetRight) }
                })
        }
        .frame(height: height)
        .onChange(of: selectedRight) { _, _ in
            changeTask?.cancel()
            guard !reduceMotion else { changing = false; return }
            changing = true
            changeTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                changing = false
            }
        }
        .onDisappear { changeTask?.cancel(); changing = false }
    }
}
