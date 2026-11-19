import SwiftUI

/// Shared drag, spring and glass treatment for the mode picker and switches.
struct SlidingCapsule<Labels: View>: View {
    let selectedRight: Bool
    let canSelectLeft: Bool
    let canSelectRight: Bool
    let selectionChanged: (Bool) -> Void
    let height: CGFloat
    let compact: Bool
    @ViewBuilder let labels: (Bool) -> Labels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @GestureState private var drag: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = compact ? 3 : 7
            let usable = max(0, geometry.size.width - inset * 2)
            let knob = compact ? height - 6 : usable / 2
            let travel = max(0, usable - knob)
            let origin = selectedRight ? travel : 0
            let offset = min(travel, max(0, origin + (drag ?? 0)))
            let proposed = travel > 0 ? offset >= travel / 2 : selectedRight
            ZStack(alignment: .leading) {
                Capsule().fill(compact && proposed ? Color.yellow.opacity(0.30) : .white.opacity(0.13))
                if #available(iOS 26, *) {
                    GlassEffectContainer {
                        Capsule().fill(.white.opacity(0.07))
                            .frame(width: knob, height: height - 6)
                            .scaleEffect(x: drag == nil || reduceMotion ? 1 : 1.08,
                                         y: drag == nil || reduceMotion ? 1 : 1.15)
                            .glassEffect(.regular.interactive(isEnabled && !reduceMotion), in: Capsule())
                            .offset(x: offset + inset)
                    }
                } else {
                    Capsule().fill(compact ? .white : .white.opacity(0.23))
                        .frame(width: knob, height: height - 6)
                        .scaleEffect(x: drag == nil || reduceMotion ? 1 : 1.08,
                                     y: drag == nil || reduceMotion ? 1 : 1.15)
                        .offset(x: offset + inset)
                }
                labels(proposed)
                    .padding(.horizontal, inset)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.76), value: drag != nil)
            .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.76), value: selectedRight)
            .contentShape(Capsule())
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .updating($drag) { value, state, _ in
                    guard isEnabled, canSelectLeft && canSelectRight, state != nil ||
                        abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = value.translation.width
                }
                .onEnded { value in
                    guard isEnabled, canSelectLeft && canSelectRight, travel > 0,
                          drag != nil || abs(value.translation.width) > abs(value.translation.height) else { return }
                    selectionChanged(origin + value.translation.width >= travel / 2)
                })
        }
        .frame(height: height)
    }
}

struct MomentraSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            Button { configuration.isOn.toggle() } label: {
                configuration.label
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(configuration.isOn ? "Ativado" : "Desativado")
            SlidingCapsule(selectedRight: configuration.isOn, canSelectLeft: true, canSelectRight: true,
                           selectionChanged: { configuration.isOn = $0 }, height: 30, compact: true) { _ in
                Color.clear.allowsHitTesting(false)
            }
            .frame(width: 51, height: 44)
            .contentShape(Rectangle())
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
            .accessibilityHidden(true)
        }
    }
}
